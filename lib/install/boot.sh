# shellcheck shell=bash
# step boot: Limine (branded in the theme's colours, with fallback path and snapshot entries) and snapper on /.

# _boot_cmdline: the running kernel command line without BOOT_IMAGE=/initrd=, plus zswap off and quiet.
_boot_cmdline() {
  local tok toks=() out=() have_zswap=0 have_quiet=0
  read -ra toks </proc/cmdline
  for tok in "${toks[@]}"; do
    case $tok in
    BOOT_IMAGE=* | initrd=*) continue ;;
    zswap.enabled=*) have_zswap=1 ;;
    quiet) have_quiet=1 ;;
    esac
    out+=("$tok")
  done
  ((have_zswap)) || out+=("zswap.enabled=0")
  ((have_quiet)) || out+=("quiet")
  printf '%s\n' "${out[*]}"
}

# _boot_head FILE: system/boot/limine.conf.head with the current theme's colours filled in.
_boot_head() {
  local head key
  theme_load
  head=$(<"$ULTRON_ROOT/system/boot/limine.conf.head")
  for key in "${!_THEME[@]}"; do
    head=${head//@"$key"@/"${_THEME[$key]}"}
  done
  if [[ "$head" =~ @[A-Z0-9_]+@ ]]; then
    die "The theme has no value for ${BASH_REMATCH[0]} (system/boot/limine.conf.head): fix the theme, then rerun: ultron install boot"
  fi
  printf '%s\n' "$head" >"$1"
}

# _boot_good FILE: FILE has a kernel entry with this command line.
_boot_good() {
  sudo grep -qE "$LIMINE_KERNEL_RE" "$1" && sudo grep -qF -- "$2" "$1"
}

step_boot() {
  local sys=$ULTRON_ROOT/system tmp tmpl cmdline hook f
  # Limine reads a limine.conf next to its EFI binary before /boot/limine.conf (the ESP root), and
  # limine-entry-tool only writes $ESP_PATH/limine.conf, so archinstall's copies must go.
  local alt=(/boot/EFI/BOOT/limine.conf /boot/EFI/limine/limine.conf /boot/EFI/arch-limine/limine.conf /boot/limine/limine.conf)

  # 1. Keep archinstall's working config once (the first-run fallback).
  if ! sudo test -e /boot/limine.conf.archinstall; then
    for f in "${alt[@]}" /boot/limine.conf; do
      if sudo test -f "$f"; then
        say "Saving archinstall's $f as /boot/limine.conf.archinstall"
        sudo cp "$f" /boot/limine.conf.archinstall
        break
      fi
    done
  fi
  sudo test -f /boot/limine.conf.archinstall || die "No Limine config from archinstall was found under /boot: nothing was changed."

  # 2. /etc/default/limine from the template. The command line comes from the running kernel on the first run,
  # then from /etc/default/limine itself (a later run may be booted from a snapshot).
  cmdline=""
  if [[ -f /etc/default/limine ]]; then
    cmdline=$(sed -n -E 's/^KERNEL_CMDLINE\[default\]="(.*)"$/\1/p' /etc/default/limine | head -n1)
  fi
  [[ -n "$cmdline" ]] || cmdline=$(_boot_cmdline)
  [[ "$cmdline" != *.snapshots* ]] || die "This boot is a snapshot (cmdline: $cmdline). Boot the normal Arch entry, then rerun: ultron install boot"
  say "Writing /etc/default/limine (cmdline: $cmdline)"
  tmpl=$(<"$sys/etc/default/limine.tmpl")
  tmp=$(mktemp)
  printf '%s\n' "${tmpl//@CMDLINE@/"$cmdline"}" >"$tmp"
  install_root "$tmp" /etc/default/limine 0644
  rm -f "$tmp"

  # 2b. Snapshots boot read-only: an overlayfs hook gives them a writable layer (limine-snapper-sync README).
  hook=btrfs-overlayfs
  if grep -qsE '^[[:space:]]*HOOKS=.*\<systemd\>' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf; then
    hook=sd-btrfs-overlayfs
  fi
  tmp=$(mktemp)
  printf '# ultron: writable overlay when booting a read-only snapshot\nHOOKS+=(%s)\n' "$hook" >"$tmp"
  install_root "$tmp" /etc/mkinitcpio.conf.d/ultron-overlayfs.conf 0644
  rm -f "$tmp"

  # 3. Keep the config that boots now: archinstall's copy points at kernel paths the Limine hook later removes,
  # so it's only the fallback until ultron has written a working config once.
  if sudo test -f /boot/limine.conf && _boot_good /boot/limine.conf "$cmdline"; then
    sudo cp /boot/limine.conf /boot/limine.conf.last-good
  fi

  # 4. Branded head; limine-update appends the entries.
  say "Writing /boot/limine.conf (ultron branding, theme colours)"
  tmp=$(mktemp)
  _boot_head "$tmp"
  install_root "$tmp" /boot/limine.conf 0644
  rm -f "$tmp"
  for f in "${alt[@]}"; do
    sudo rm -f "$f"
  done

  # 5. Install, rebuild the initramfs and generate entries.
  say "Installing Limine and generating boot entries"
  sudo limine-install || warn "limine-install failed (no NVRAM entry); the fallback path \\EFI\\BOOT\\BOOTX64.EFI still boots"
  sudo limine-install --fallback || warn "limine-install --fallback failed"
  sudo limine-update || warn "limine-update failed"

  # 6. Never leave an unbootable config behind.
  if ! _boot_good /boot/limine.conf "$cmdline"; then
    if sudo test -f /boot/limine.conf.last-good; then
      sudo cp /boot/limine.conf.last-good /boot/limine.conf
    else
      sudo cp /boot/limine.conf.archinstall /boot/limine.conf
      sudo install -D -m 0644 /boot/limine.conf.archinstall /boot/EFI/BOOT/limine.conf
    fi
    die "The new /boot/limine.conf had no kernel entry or lost the kernel command line, so the last working config was put back. Rerun: ultron install boot"
  fi
  ok "/boot/limine.conf has the kernel entry and command line"

  # 7. snapper config for / (creates the /.snapshots subvolume).
  if ! sudo test -f /etc/snapper/configs/root; then
    say "Creating the snapper config for /"
    sudo snapper -c root create-config /
  fi

  # 8. ultron's snapper settings: max 5 snapshots, no timeline.
  say "Installing the snapper config (5 snapshots, no timeline)"
  install_root "$sys/etc/snapper/configs/root" /etc/snapper/configs/root 0644
  install_root "$sys/etc/conf.d/snapper" /etc/conf.d/snapper 0644

  # 9. Timers and the snapshot -> boot menu sync.
  sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true
  sudo systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service

  # 10. First snapshot, once. It rotates away like any other (a permanent one would pin the install-time
  # blocks forever), so "once" is remembered in a marker file, not by looking for the snapshot.
  if sudo test -e /var/lib/ultron/first-snapshot; then
    ok "The first snapshot was taken earlier"
  else
    say "Taking the first snapshot"
    sudo snapper -c root create -c number -d "ultron install"
    sudo install -D -m 0644 /dev/null /var/lib/ultron/first-snapshot
  fi

  # 11. The rewrite above dropped the Snapshots entries; put them back now instead of at the next snapshot.
  if have limine-snapper-sync; then
    sudo limine-snapper-sync || warn "limine-snapper-sync failed: the Snapshots menu is filled again at the next snapshot"
  fi
}
