#!/usr/bin/env bash
# ultron bootstrap: runs as root in the Arch live ISO (UEFI) and installs the base system with archinstall.
#   bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)
# Standalone on purpose: the ISO has no checkout, so lib/common.sh is not available here.
set -euo pipefail

REPO_URL="https://github.com/zhivko-kocev/ultron"
TMPL_URL="https://raw.githubusercontent.com/zhivko-kocev/ultron/main/install/archinstall.json.tmpl"
USER_NAME="zhivko-kocev"
HOST_NAME="ultron"
TIME_ZONE="Europe/Skopje"
SSD_UUID="f4d0a7a7-ee8c-458c-91aa-3f2dceacb527"
SSD_LABEL="projects"
WORK=/tmp/ultron
CONFIG="$WORK/user_configuration.json"
CREDS="$WORK/user_credentials.json"
INSTALL_LOG=/var/log/archinstall/install.log
# ESP: start 1 MiB, size 2 GiB (fixed in install/archinstall.json.tmpl).
ROOT_START=2148532224        # 2 GiB + 1 MiB
TAIL_GAP=1048576             # leave 1 MiB free at the end

say() { printf '\e[1;33m==>\e[0m %s\n' "$*"; }
die() {
  printf '\e[1;31merror\e[0m %s\n' "$*" >&2
  exit 1
}

# ---- 1. checks ----------------------------------------------------------------

checks() {
  say "Checking the live environment"
  [[ $EUID -eq 0 ]] || die "Run this as root (the Arch live ISO logs you in as root)."
  [[ -d /sys/firmware/efi/efivars ]] ||
    die "You started the USB in legacy mode: reboot, press F12, pick the entry that starts with UEFI:"
  curl -fsI https://archlinux.org >/dev/null 2>&1 ||
    die "No internet. Plug in the network cable (or run iwctl for Wi-Fi), then run this again."
  local ver
  ver=$(archinstall --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1 || true)
  [[ "$ver" == 4.* ]] ||
    die "This needs archinstall 4.x, but found '${ver:-none}'. Use the archlinux-2026.11.01 ISO or newer."
  if ! command -v jq >/dev/null 2>&1; then
    say "Installing jq into the live system (needed to write the config files)"
    pacman -Sy --noconfirm --needed jq >/dev/null || die "Couldn't install jq in the live system."
  fi
}

# ---- 2. disk ------------------------------------------------------------------

DISK="" DISK_BYTES=0

# Whole-disk device of the live medium (empty when unknown).
live_disk() {
  local src pk
  src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  [[ -n "$src" ]] || return 0
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
  if [[ -n "$pk" ]]; then printf '/dev/%s\n' "$pk"; else printf '%s\n' "$src"; fi
}

# True when the disk holds the projects SSD partition (by UUID or label).
holds_projects() {
  lsblk -nPo UUID,LABEL "$1" 2>/dev/null | grep -qE "UUID=\"$SSD_UUID\"|LABEL=\"$SSD_LABEL\""
}

pick_disk() {
  say "Finding the disk to install on"
  local live names=() sizes=() models=() trans=() bytes=() name size model tran type b
  live=$(live_disk)
  # Fields are joined with US (0x1f), not tabs, so empty MODEL/TRAN fields don't collapse.
  while IFS=$'\x1f' read -r name b model tran type; do
    [[ "$type" == disk ]] || continue
    [[ "$name" == /dev/loop* || "$name" == /dev/zram* || "$name" == /dev/sr* ]] && continue
    [[ -n "$live" && "$name" == "$live" ]] && continue
    holds_projects "$name" && continue
    size=$(numfmt --to=iec --suffix=B "$b")
    names+=("$name") sizes+=("$size") models+=("${model:--}") trans+=("${tran:--}") bytes+=("$b")
  done < <(lsblk -J -dpb -o NAME,SIZE,MODEL,TRAN,TYPE |
    jq -r '.blockdevices[] | [.name, (.size | tostring), (.model // "" | gsub("^\\s+|\\s+$"; "")), (.tran // ""), .type] | join("\u001f")')

  ((${#names[@]} > 0)) || die "No disk to install on was found (the USB stick and the projects SSD are never offered)."

  local def="" i
  for i in "${!names[@]}"; do
    if systemd-detect-virt -q --vm; then
      [[ "${names[$i]}" == /dev/vda ]] && def=$((i + 1))
    elif [[ "${models[$i]^^}" == *KIOXIA* ]]; then
      def=$((i + 1))
    fi
  done

  echo "Disks that can be erased:"
  for i in "${!names[@]}"; do
    printf '  %d) %-14s %8s  %s  (%s)\n' "$((i + 1))" "${names[$i]}" "${sizes[$i]}" "${models[$i]}" "${trans[$i]}"
  done
  local choice
  read -rp "Install on which disk? [${def:-pick a number}] " choice
  choice=${choice:-$def}
  { [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#names[@]})); } || die "No disk picked: nothing was changed."
  i=$((choice - 1))
  DISK=${names[$i]} DISK_BYTES=${bytes[$i]}

  echo
  echo "EVERYTHING on ${DISK} (${models[$i]}, ${sizes[$i]}) will be erased."
  local answer
  read -rp "Type wipe to continue: " answer
  [[ "$answer" == wipe ]] || die "You didn't type wipe: nothing was changed."
}

# ---- 3. passwords ---------------------------------------------------------------

DISK_PW="" USER_PW=""

# ask_twice VAR LABEL: read a non-empty password twice into VAR.
ask_twice() {
  local -n _out=$1
  local a b
  while true; do
    read -rsp "$2: " a
    echo
    read -rsp "$2 again: " b
    echo
    if [[ -z "$a" ]]; then
      echo "The password can't be empty."
    elif [[ "$a" != "$b" ]]; then
      echo "They don't match, try again."
    else
      break
    fi
  done
  _out=$a
}

passwords() {
  say "Passwords"
  ask_twice DISK_PW "Disk password (typed at every power-on)"
  local same
  read -rp "Use the same password for your user ($USER_NAME)? [Y/n] " same
  if [[ -z "$same" || "$same" =~ ^[Yy] ]]; then
    USER_PW=$DISK_PW
  else
    ask_twice USER_PW "User password"
  fi
}

# ---- 4. config files --------------------------------------------------------------

template() {
  local here
  here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  if [[ -f "$here/install/archinstall.json.tmpl" ]]; then
    cat "$here/install/archinstall.json.tmpl"
  else
    curl -fsSL "$TMPL_URL" || die "Couldn't download $TMPL_URL"
  fi
}

write_configs() {
  say "Writing the archinstall configuration"
  local mib=1048576 floored root_size
  floored=$((DISK_BYTES / mib * mib))
  root_size=$((floored - ROOT_START - TAIL_GAP))
  ((root_size >= 20 * 1024 * mib)) || die "$DISK is too small (needs at least 23 GiB)."

  umask 077
  mkdir -p "$WORK"
  # @ROOT_SIZE@ is a bare number in the template: quote it so the template parses as JSON,
  # then jq swaps every placeholder string for its value (jq does all escaping).
  template | sed -E 's/"?@ROOT_SIZE@"?/"@ROOT_SIZE@"/g' |
    jq --arg disk "$DISK" --arg host "$HOST_NAME" --arg tz "$TIME_ZONE" --argjson size "$root_size" '
      walk(if . == "@DISK@" then $disk
           elif . == "@HOSTNAME@" then $host
           elif . == "@TIMEZONE@" then $tz
           elif . == "@ROOT_SIZE@" then $size
           else . end)' >"$CONFIG" ||
    die "The archinstall template isn't valid JSON."
  ! grep -qE '@[A-Z_]+@' "$CONFIG" || die "The archinstall template has a placeholder this script doesn't know."
  jq . "$CONFIG" >/dev/null || die "The archinstall configuration isn't valid JSON."
  echo "Config written to $CONFIG."

  jq -n --arg disk_pw "$DISK_PW" --arg user "$USER_NAME" --arg user_pw "$USER_PW" '
    {encryption_password: $disk_pw,
     users: [{username: $user, "!password": $user_pw, sudo: true, groups: []}]}' >"$CREDS"
  chmod 600 "$CREDS"
  DISK_PW="" USER_PW=""
  echo "Disk: $DISK, root partition: $((root_size / mib)) MiB (encrypted btrfs), ESP: 2 GiB."
}

# ---- 5. install -------------------------------------------------------------------

# release_disk: undo what an earlier, failed run left behind (mounts under /mnt, open LUKS on DISK),
# or archinstall can't wipe the disk.
release_disk() {
  local dev
  if mountpoint -q /mnt; then
    say "Unmounting /mnt left by an earlier run"
    umount -R /mnt || die "Couldn't unmount /mnt. Reboot the USB stick and run this again."
  fi
  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    say "Closing $dev left open by an earlier run"
    cryptsetup close "$dev" || die "Couldn't close $dev. Reboot the USB stick and run this again."
  done < <(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2 == "crypt" { print $1 }')
}

run_archinstall() {
  release_disk
  say "Installing Arch with archinstall (this takes a while)"
  # kb_layout is empty in the template: archinstall would otherwise boot the new system in a container to
  # run localectl, which failed in testing ("Failed to connect to system scope bus via machine transport").
  # The console keymap is written by finish() instead.
  if ! archinstall --config "$CONFIG" --creds "$CREDS" --silent; then
    shred -u "$CREDS" 2>/dev/null || rm -f "$CREDS"
    cat >&2 <<EOF

archinstall failed. Its log is $INSTALL_LOG.
If it failed at the bootloader, finish by hand (docs/migrate.md, "archinstall fails at the bootloader"):
  arch-chroot /mnt
  pacman -S limine
  install -D /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
  write /boot/limine.conf with one entry:
    /Arch Linux
        protocol: linux
        kernel_path: boot():/vmlinuz-linux
        module_path: boot():/initramfs-linux.img
        cmdline: rd.luks.name=<blkid UUID of the 2nd partition>=root root=/dev/mapper/root rootflags=subvol=@ rw quiet
Then reboot and continue with: ~/Projects/ultron/bin/ultron install
EOF
    exit 1
  fi
}

# ---- 6. after the install -----------------------------------------------------------

finish() {
  shred -u "$CREDS" 2>/dev/null || rm -f "$CREDS"
  if ! mountpoint -q /mnt; then
    echo "warn: nothing is mounted at /mnt; after reboot run: git clone $REPO_URL ~/Projects/ultron" >&2
  else
    say "Cloning ultron into the new system"
    arch-chroot /mnt runuser -u "$USER_NAME" -- git clone "$REPO_URL" "/home/$USER_NAME/Projects/ultron" ||
      echo "warn: the clone failed; after reboot run: git clone $REPO_URL ~/Projects/ultron" >&2
    printf 'Next: run ~/Projects/ultron/bin/ultron install\n' >/mnt/etc/motd
    printf 'KEYMAP=us\nFONT=default8x16\n' >/mnt/etc/vconsole.conf
  fi
  echo
  say "Done. Remove the USB stick, reboot, type the disk password, log in, run the motd command."
}

main() {
  checks
  pick_disk
  passwords
  write_configs
  run_archinstall
  finish
}

main "$@"
