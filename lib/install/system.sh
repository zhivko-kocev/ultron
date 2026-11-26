# shellcheck shell=bash
# step system: root-owned system files, sudo askpass, extra disks (MOUNTS), firewall,
# rootless Docker ID ranges and boot-time services.

# Files under system/ that other steps own:
#   etc/default/limine.tmpl, boot/  -> step_boot (filled from /proc/cmdline and the theme)
#   etc/snapper/, etc/conf.d/snapper -> step_boot (snapper create-config refuses an existing config)
#   etc/ntfy/                        -> step_ntfy (needs secrets)
#   etc/systemd/system/ollama.service.d/ -> step_ai (adds the GPU pin, restarts ollama only on change)
_system_skip() {
  case $1 in
  etc/default/limine.tmpl | boot/* | etc/ntfy/* | etc/snapper/* | etc/conf.d/snapper | etc/systemd/system/ollama.service.d/*) return 0 ;;
  esac
  return 1
}

# Only files git tracks: whatever else lies in system/ (editor backups, experiments) never reaches /.
_system_files() {
  say "Copying system files to / (root-owned, not linked)"
  local rel src mode tmp pin content
  pin=$(omp_pin)
  while IFS= read -r -d '' rel; do
    rel=${rel#system/}
    if _system_skip "$rel"; then continue; fi
    src=$ULTRON_ROOT/system/$rel
    [[ -f "$src" ]] || die "$src is tracked but missing: restore it (git checkout -- system/$rel)"
    mode=0644
    if [[ -x "$src" ]]; then mode=0755; fi
    content=$(<"$src")
    content=${content//@USER@/"$ULTRON_USER"}
    if [[ "/$rel" == "$ULTRON_TOOLS_CONF" && -n "$pin" ]]; then
      # Keep the omp version step_jocasta pinned from Jocasta's README.
      content=$(sed -E "s/^([[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\"$pin\"/" <<<"$content")
    fi
    tmp=$(mktemp)
    printf '%s\n' "$content" >"$tmp"
    install_root "$tmp" "/$rel" "$mode"
    rm -f "$tmp"
    echo "  /$rel"
  done < <(git -C "$ULTRON_ROOT" ls-files -z -- system)
}

_system_askpass() {
  if ! grep -qE '^[[:space:]]*Path[[:space:]]+askpass[[:space:]]+/usr/lib/ultron/askpass' /etc/sudo.conf 2>/dev/null; then
    say "Pointing sudo -A at /usr/lib/ultron/askpass (/etc/sudo.conf)"
    printf 'Path askpass /usr/lib/ultron/askpass\n' | sudo tee -a /etc/sudo.conf >/dev/null
  fi
}

# _system_mounts: every MOUNTS entry in fstab (nofail, so a missing disk never stops the boot), mounted now.
# Each line ultron writes has a "# ultron MOUNTS" line above it, so a changed or removed entry is taken out.
_system_mounts() {
  local spec mp dev fstype line old before mps=()
  before=$(cat /etc/fstab)
  old=$(sed -n '/^# ultron MOUNTS$/{n;p}' /etc/fstab)
  sudo sed -i '/^# ultron MOUNTS$/,+1d' /etc/fstab
  while read -r -u 3 spec mp; do
    [[ -n "$spec" ]] || continue
    case $spec in
    LABEL=* | UUID=*) dev=$(sudo blkid -o device -t "$spec" 2>/dev/null | head -n1 || true) ;;
    /dev/*) if [[ -b "$spec" ]]; then dev=$spec; else dev=""; fi ;;
    *)
      warn "MOUNTS: '$spec' isn't LABEL=x, UUID=x or /dev/x: skipped"
      continue
      ;;
    esac
    if [[ -z "$dev" ]]; then
      # A disk that isn't connected now keeps the line ultron wrote for it earlier.
      line=$(awk -v s="$spec" -v m="$mp" '$1 == s && $2 == m { print; exit }' <<<"$old")
      if [[ -n "$line" ]]; then
        printf '# ultron MOUNTS\n%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
        warn "MOUNTS: no disk matches $spec (not connected?): its fstab line stays, not mounted now"
      else
        warn "MOUNTS: no disk matches $spec (not connected?): skipped $mp"
      fi
      continue
    fi
    fstype=$(sudo blkid -o value -s TYPE "$dev" 2>/dev/null || true)
    [[ -n "$fstype" ]] || {
      warn "MOUNTS: $dev ($spec) has no filesystem blkid recognises: skipped"
      continue
    }
    if awk -v s="$spec" -v m="$mp" '!/^[[:space:]]*#/ && ($1 == s || $2 == m) { f = 1 } END { exit !f }' /etc/fstab; then
      echo "  $spec $mp: already in /etc/fstab (a line ultron didn't write)"
    else
      echo "  $spec ($fstype) at $mp (nofail)"
      printf '# ultron MOUNTS\n%s %s %s defaults,noatime,nofail,x-systemd.device-timeout=5s 0 2\n' "$spec" "$mp" "$fstype" |
        sudo tee -a /etc/fstab >/dev/null
    fi
    sudo mkdir -p "$mp"
    mps+=("$mp")
  done 3< <(conf_mounts)
  if [[ "$(cat /etc/fstab)" != "$before" ]]; then
    say "/etc/fstab changed: reloading systemd's mount units"
    sudo systemctl daemon-reload
  fi
  for mp in "${mps[@]}"; do
    if ! mountpoint -q "$mp"; then
      sudo mount "$mp" || warn "Couldn't mount $mp now (see above); it's tried again at every boot"
    fi
  done
}

_system_firewall() {
  local extra tok rules=()
  conf_var extra FIREWALL_ALLOW
  local -a toks=()
  read -ra toks <<<"$extra"
  for tok in "${toks[@]}"; do
    if [[ "$tok" =~ ^[0-9]+(:[0-9]+)?/(tcp|udp)$ ]]; then
      rules+=("$tok")
    else
      warn "FIREWALL_ALLOW: '$tok' isn't PORT/tcp, PORT/udp or FROM:TO/proto: skipped"
    fi
  done
  say "Firewall: block incoming except Tailscale${rules[*]:+ and ${rules[*]}}"
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw allow in on tailscale0 >/dev/null
  # ultron's rules carry the comment "ultron": the ones no longer in FIREWALL_ALLOW are deleted.
  local t
  while read -r t; do
    if [[ -n "$t" ]] && ! _in_list "$t" "${rules[@]}"; then
      echo "  closing $t (no longer in FIREWALL_ALLOW)"
      sudo ufw delete allow "$t" >/dev/null
    fi
  done < <(sudo ufw show added | awk -v c="'ultron'" '$1 == "ufw" && $2 == "allow" && $4 == "comment" && $5 == c { print $3 }')
  for tok in "${rules[@]}"; do
    sudo ufw allow "$tok" comment ultron >/dev/null
  done
  sudo ufw --force enable >/dev/null
  # --now: `ufw enable` loads the rules but leaves ufw.service inactive until the next boot.
  sudo systemctl enable --now ufw
}

_system_subids() {
  if ! grep -q "^$ULTRON_USER:" /etc/subuid 2>/dev/null; then
    say "Giving $ULTRON_USER subordinate IDs for rootless Docker"
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$ULTRON_USER"
  fi
}

step_system() {
  _system_files
  _system_askpass
  _system_mounts
  _system_firewall
  _system_subids
  say "Enabling greetd, fstrim.timer and paccache.timer (they start on the next boot)"
  sudo systemctl enable greetd fstrim.timer paccache.timer
  sudo rm -f /etc/motd
}
