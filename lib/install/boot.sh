# shellcheck shell=bash
# step boot: Limine (branded, with fallback path and snapshot entries) and snapper on /.

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

step_boot() {
  local sys=$ULTRON_ROOT/system tmp tmpl cmdline hook f
  # Limine reads a limine.conf next to its EFI binary before /boot/limine.conf (the ESP root), and
  # limine-entry-tool only writes $ESP_PATH/limine.conf, so archinstall's copies must go.
  local alt=(/boot/EFI/BOOT/limine.conf /boot/EFI/limine/limine.conf /boot/EFI/arch-limine/limine.conf /boot/limine/limine.conf)

  # 1. Keep archinstall's working config once.
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
  [[ -f /etc/default/limine ]] && cmdline=$(sed -n -E 's/^KERNEL_CMDLINE\[default\]="(.*)"$/\1/p' /etc/default/limine | head -n1)
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
  if grep -h '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf 2>/dev/null | grep -qw systemd; then
    hook=sd-btrfs-overlayfs
  fi
  tmp=$(mktemp)
  printf '# ultron: writable overlay when booting a read-only snapshot\nHOOKS+=(%s)\n' "$hook" >"$tmp"
  install_root "$tmp" /etc/mkinitcpio.conf.d/ultron-overlayfs.conf 0644
  rm -f "$tmp"

  # 3. Branded head; limine-update appends the entries.
  say "Writing /boot/limine.conf (ultron branding, Gruvbox)"
  sudo cp "$sys/boot/limine.conf.head" /boot/limine.conf
  for f in "${alt[@]}"; do
    sudo rm -f "$f"
  done

  # 4. Install, rebuild the initramfs and generate entries.
  say "Installing Limine and generating boot entries"
  sudo limine-install || warn "limine-install failed (no NVRAM entry); the fallback path \\EFI\\BOOT\\BOOTX64.EFI still boots"
  sudo limine-install --fallback || warn "limine-install --fallback failed"
  sudo limine-update || warn "limine-update failed"

  # 5. Never leave an unbootable config behind. Limine 9+ names the kernel `path:` (older: `kernel_path:`).
  if ! sudo grep -qE '^[[:space:]]*(kernel_)?path:[[:space:]]*boot\(\)' /boot/limine.conf ||
    ! sudo grep -qF -- "$cmdline" /boot/limine.conf; then
    sudo cp /boot/limine.conf.archinstall /boot/limine.conf
    sudo install -D -m 0644 /boot/limine.conf.archinstall /boot/EFI/BOOT/limine.conf
    die "The new /boot/limine.conf had no kernel entry or lost the kernel command line, so archinstall's config was put back. Rerun: ultron install boot"
  fi
  ok "/boot/limine.conf has the kernel entry and command line"

  # 6. snapper config for / (creates the /.snapshots subvolume).
  if ! sudo test -f /etc/snapper/configs/root; then
    say "Creating the snapper config for /"
    sudo snapper -c root create-config /
  fi

  # 7. ultron's snapper settings: max 5 snapshots, no timeline.
  say "Installing the snapper config (5 snapshots, no timeline)"
  install_root "$sys/etc/snapper/configs/root" /etc/snapper/configs/root 0644
  install_root "$sys/etc/conf.d/snapper" /etc/conf.d/snapper 0644

  # 8. Timers and the snapshot -> boot menu sync.
  sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true
  sudo systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service

  # 9. First snapshot.
  say "Taking the first snapshot"
  sudo snapper -c root create -d "ultron install" -c number
}
