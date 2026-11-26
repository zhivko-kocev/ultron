# shellcheck shell=bash
# step system: root-owned system files, sudo askpass, the projects SSD, firewall,
# rootless Docker ID ranges and boot-time services.

# Files under system/ that other steps own:
#   etc/default/limine.tmpl, boot/  -> step_boot (filled from /proc/cmdline)
#   etc/snapper/, etc/conf.d/snapper -> step_boot (snapper create-config refuses an existing config)
#   etc/ntfy/                        -> step_ntfy (needs secrets)
_system_skip() {
  case $1 in
  etc/default/limine.tmpl | boot/* | etc/ntfy/* | etc/snapper/* | etc/conf.d/snapper) return 0 ;;
  esac
  return 1
}

_system_files() {
  say "Copying system files to / (root-owned, not linked)"
  local src rel mode tmp pin
  while IFS= read -r -d '' src; do
    rel=${src#"$ULTRON_ROOT/system/"}
    _system_skip "$rel" && continue
    mode=0644
    [[ -x "$src" ]] && mode=0755
    if [[ "/$rel" == "$ULTRON_TOOLS_CONF" ]] && pin=$(omp_pin) && [[ -n "$pin" ]]; then
      # Keep the omp version step_jocasta pinned from Jocasta's README.
      tmp=$(mktemp)
      sed -E "s/^([[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\"$pin\"/" "$src" >"$tmp"
      install_root "$tmp" "/$rel" "$mode"
      rm -f "$tmp"
    else
      install_root "$src" "/$rel" "$mode"
    fi
    echo "  /$rel"
  done < <(find "$ULTRON_ROOT/system" -type f -print0 | sort -z)
}

_system_askpass() {
  if ! grep -qE '^[[:space:]]*Path[[:space:]]+askpass[[:space:]]+/usr/lib/ultron/askpass' /etc/sudo.conf 2>/dev/null; then
    say "Pointing sudo -A at /usr/lib/ultron/askpass (/etc/sudo.conf)"
    printf 'Path askpass /usr/lib/ultron/askpass\n' | sudo tee -a /etc/sudo.conf >/dev/null
  fi
}

_system_ssd() {
  if is_vm; then
    echo "  VM: skipping the projects SSD"
    return 0
  fi
  if ! sudo blkid -U "$SSD_UUID" >/dev/null 2>&1; then
    warn "The projects SSD (UUID $SSD_UUID) isn't connected: skipping its mount"
    return 0
  fi
  say "Mounting the projects SSD at $SSD_MOUNT on every boot (nofail)"
  sudo mkdir -p "$SSD_MOUNT"
  if ! grep -q "UUID=$SSD_UUID" /etc/fstab; then
    printf 'UUID=%s %s ext4 defaults,noatime,nofail,x-systemd.device-timeout=5s 0 2\n' "$SSD_UUID" "$SSD_MOUNT" |
      sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
  fi
}

_system_firewall() {
  say "Firewall: block incoming except Tailscale and LocalSend (53317)"
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw allow in on tailscale0 >/dev/null
  sudo ufw allow 53317/tcp >/dev/null
  sudo ufw allow 53317/udp >/dev/null
  sudo ufw --force enable >/dev/null
  sudo systemctl enable ufw
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
  _system_ssd
  _system_firewall
  _system_subids
  say "Enabling greetd, fstrim.timer and paccache.timer (they start on the next boot)"
  sudo systemctl enable greetd fstrim.timer paccache.timer
  sudo rm -f /etc/motd
}
