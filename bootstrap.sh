#!/usr/bin/env bash
# ultron bootstrap: runs as root in the Arch live ISO (UEFI) and installs the base system with archinstall.
# The ultron ISO (iso/build) starts it on the first console; on a stock Arch ISO paste:
#   bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)
# Standalone on purpose: the ISO has no checkout, so lib/common.sh is not available here.
# Offline with a Wi-Fi card, it offers a network list first; the joined network is carried over to the new
# system, whose first boot logs in on tty1 and continues with `ultron install --first-boot`.
#
# Every answer can come from the environment (a set variable skips its question):
#   ULTRON_USER       your login name (asked when unset)
#   ULTRON_HOSTNAME   computer name (default ultron)
#   ULTRON_TIMEZONE   e.g. Europe/Berlin (default: detected from your IP address, else UTC)
#   ULTRON_KEYBOARD   XKB layout(s), e.g. us or de,us (default us); the console uses the first one
#   ULTRON_DOTFILES   optional dotfiles repo: owner/repo (GitHub) or a git URL
#   ULTRON_DISK       disk to erase, e.g. /dev/nvme0n1
#   ULTRON_KEEP       comma-separated partition labels or UUIDs: disks holding one are never offered
#   ULTRON_REPO       ultron repo to clone (default https://github.com/zhivko-kocev/ultron)
#   ULTRON_REF        branch or tag of it (default main)
#   ULTRON_TMPL_URL   where to fetch install/archinstall.json.tmpl (default: from ULTRON_REPO at ULTRON_REF)
# With all of them set, stdin is read for exactly: wipe, the disk password twice, the same-password answer
# (then the user password twice when that answer is n).
set -euo pipefail

REPO_URL=${ULTRON_REPO:-https://github.com/zhivko-kocev/ultron}
REPO_REF=${ULTRON_REF:-main}
WORK=/tmp/ultron
CONFIG="$WORK/user_configuration.json"
CREDS="$WORK/user_credentials.json"
INSTALL_LOG=/var/log/archinstall/install.log
# ESP: start 1 MiB, size 2 GiB (fixed in install/archinstall.json.tmpl).
ROOT_START=2148532224 # 2 GiB + 1 MiB
TAIL_GAP=1048576      # leave 1 MiB free at the end

say() { printf '\e[1;33m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;35mwarn\e[0m %s\n' "$*" >&2; }
die() {
  printf '\e[1;31merror\e[0m %s\n' "$*" >&2
  exit 1
}

# The credentials file holds both passwords: it never outlives this script, however it ends.
cleanup() {
  if [[ -e "$CREDS" ]]; then shred -u "$CREDS" 2>/dev/null || rm -f "$CREDS"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# ---- 1. checks ----------------------------------------------------------------

online() { curl -fsI --max-time 10 https://archlinux.org >/dev/null 2>&1; }

# wifi_dev: the first wireless network device (fails when there is none).
wifi_dev() {
  local d
  for d in /sys/class/net/*/wireless; do
    [[ -e "$d" ]] || continue
    d=${d%/wireless}
    printf '%s\n' "${d##*/}"
    return 0
  done
  return 1
}

# iwctl colours its tables even when piped.
plain() { sed -E 's/\x1b\[[0-9;]*m//g'; }

# connected_ssid DEV: the network DEV is joined to (empty when none).
connected_ssid() {
  { iwctl station "$1" show 2>/dev/null || true; } | plain |
    sed -n -E '/^[[:space:]]*Connected network[[:space:]]/{s/^[[:space:]]*Connected network[[:space:]]+(.*[^[:space:]])[[:space:]]*$/\1/p;q}'
}

# join_wifi DEV: pick a network from a list, type its password, wait until the internet answers.
# Loops until it's online; a failure says why and shows the list again.
join_wifi() {
  local dev=$1 line ssid pw out i
  local re='^[[:space:]>]*(.*[^[:space:]])[[:space:]]+(open|psk|8021x|wep)[[:space:]]+[*]*[[:space:]]*$'
  local -a names kinds
  rfkill unblock wifi 2>/dev/null || true
  while true; do
    say "Looking for Wi-Fi networks"
    iwctl station "$dev" scan >/dev/null 2>&1 || true
    sleep 3
    names=() kinds=()
    while IFS= read -r line; do
      if [[ "$line" =~ $re ]]; then
        names+=("${BASH_REMATCH[1]}")
        kinds+=("${BASH_REMATCH[2]}")
      fi
    done < <({ iwctl station "$dev" get-networks 2>/dev/null || true; } | plain)
    echo "Pick your Wi-Fi network (or plug in a network cable and pick 'Scan again'):"
    PS3="Number: "
    ssid=""
    select ssid in "${names[@]}" "Scan again"; do
      [[ -n "$ssid" ]] && break
      echo "Type one of the numbers above."
    done
    [[ -n "$ssid" ]] || die "No network picked. Run this again when you're ready."
    if online; then return 0; fi
    [[ "$ssid" != "Scan again" ]] || continue
    for i in "${!names[@]}"; do
      if [[ "${names[i]}" == "$ssid" ]]; then break; fi
    done
    case ${kinds[i]} in
    8021x)
      warn "$ssid is an enterprise (802.1X) network: this installer can't join it. Pick another one or plug in a cable."
      continue
      ;;
    open) pw="" ;;
    *)
      read -r -s -p "Password for $ssid: " pw
      echo
      ;;
    esac
    say "Joining $ssid"
    if [[ -n "$pw" ]]; then
      out=$(iwctl --passphrase "$pw" station "$dev" connect "$ssid" 2>&1) || true
    else
      out=$(iwctl station "$dev" connect "$ssid" 2>&1) || true
    fi
    pw=""
    if [[ "$(connected_ssid "$dev")" != "$ssid" ]]; then
      warn "Couldn't join $ssid${out:+: $(printf '%s' "$out" | plain | tr -s '\n' ' ')} (a wrong password is the usual cause)."
      continue
    fi
    for i in {1..10}; do
      if online; then
        say "Online through $ssid"
        return 0
      fi
      sleep 2
    done
    warn "Joined $ssid, but the internet didn't answer within 20 s (a network with a sign-in page doesn't work here)."
  done
}

checks() {
  say "Checking the live environment"
  [[ $EUID -eq 0 ]] || die "Run this as root (the Arch live ISO logs you in as root)."
  [[ -d /sys/firmware/efi/efivars ]] ||
    die "The USB stick started in legacy (BIOS) mode: reboot, open the boot menu and pick the entry that starts with UEFI:"
  if ! online; then
    local dev
    dev=$(wifi_dev) ||
      die "No internet. Plug in a network cable (or fix the connection), then run this again."
    join_wifi "$dev"
  fi
  local ver
  ver=$(archinstall --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1 || true)
  [[ "$ver" == 4.* ]] ||
    die "This needs archinstall 4.x, but found '${ver:-none}'. Use the archlinux-2026.11.01 ISO or newer."
  if ! command -v jq >/dev/null 2>&1; then
    say "Installing jq into the live system (needed to write the config files)"
    pacman -Sy --noconfirm --needed jq >/dev/null || die "Couldn't install jq in the live system."
  fi
}

# ---- 2. settings ----------------------------------------------------------------

USER_NAME="" HOST_NAME="" TIME_ZONE="" KEYBOARD="" CONSOLE_KEYMAP="" DOTFILES_URL=""

# ask VAR PROMPT DEFAULT: one line from the user into VAR (DEFAULT on Enter).
ask() {
  local -n _ans=$1
  local reply
  read -rp "$2${3:+ [$3]}: " reply
  _ans=${reply:-$3}
}

valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$1" != root ]]; }
valid_host() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; }
valid_tz() { [[ "$1" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ && -f "/usr/share/zoneinfo/$1" ]]; }
valid_kb() { [[ "$1" =~ ^[a-z][a-z0-9_-]*(,[a-z][a-z0-9_-]*)*$ ]]; }

# detect_timezone: a guess from the public IP address (these services rate-limit, so several are tried).
# It is only the default of a question, and only a name that exists in /usr/share/zoneinfo is used.
detect_timezone() {
  local url tz
  for url in https://ipapi.co/timezone https://ipinfo.io/timezone 'http://ip-api.com/line?fields=timezone'; do
    tz=$(curl -fsS --max-time 4 "$url" 2>/dev/null || true)
    if valid_tz "$tz"; then
      printf '%s\n' "$tz"
      return 0
    fi
  done
  printf 'UTC\n'
}

# console_keymap LAYOUTS: the console keymap for the first XKB layout ("us" when kbd has none).
console_keymap() {
  local km=${1%%,*}
  [[ "$km" != gb ]] || km=uk
  if [[ -n "$(find /usr/share/kbd/keymaps -name "$km.map*" -print -quit 2>/dev/null)" ]]; then
    printf '%s\n' "$km"
  else
    printf 'us\n'
  fi
}

settings() {
  say "Settings (set ULTRON_* variables to skip these questions)"
  if [[ -n "${ULTRON_USER:-}" ]]; then
    USER_NAME=$ULTRON_USER
    valid_user "$USER_NAME" || die "ULTRON_USER '$USER_NAME' isn't a valid login name (lowercase letters, digits, _ and -, starting with a letter or _)."
  else
    while true; do
      ask USER_NAME "Your login name (lowercase, e.g. alex)" ""
      valid_user "$USER_NAME" && break
      echo "Use lowercase letters, digits, _ and -, starting with a letter or _ (at most 32 characters, not root)."
    done
  fi

  if [[ -n "${ULTRON_HOSTNAME:-}" ]]; then
    HOST_NAME=$ULTRON_HOSTNAME
    valid_host "$HOST_NAME" || die "ULTRON_HOSTNAME '$HOST_NAME' isn't a valid computer name (letters, digits and -, at most 63)."
  else
    while true; do
      ask HOST_NAME "Computer name" ultron
      valid_host "$HOST_NAME" && break
      echo "Use letters, digits and - (not at the start or end), at most 63 characters."
    done
  fi

  if [[ -n "${ULTRON_TIMEZONE:-}" ]]; then
    TIME_ZONE=$ULTRON_TIMEZONE
    valid_tz "$TIME_ZONE" || die "ULTRON_TIMEZONE '$TIME_ZONE' isn't a time zone (see ls /usr/share/zoneinfo), e.g. Europe/Berlin."
  else
    local detected
    detected=$(detect_timezone)
    while true; do
      ask TIME_ZONE "Time zone" "$detected"
      valid_tz "$TIME_ZONE" && break
      echo "Not a time zone. Examples: Europe/Berlin, America/New_York, Asia/Tokyo, UTC."
    done
  fi

  if [[ -n "${ULTRON_KEYBOARD:-}" ]]; then
    KEYBOARD=$ULTRON_KEYBOARD
    valid_kb "$KEYBOARD" || die "ULTRON_KEYBOARD '$KEYBOARD' isn't an XKB layout list, e.g. us or de,us."
  else
    while true; do
      ask KEYBOARD "Keyboard layout (XKB, e.g. us, de, fr, gb; several: de,us)" us
      valid_kb "$KEYBOARD" && break
      echo "Use XKB layout names separated by commas, e.g. us or de,us."
    done
  fi
  CONSOLE_KEYMAP=$(console_keymap "$KEYBOARD")
  if [[ "$CONSOLE_KEYMAP" == us && "${KEYBOARD%%,*}" != us ]]; then
    warn "The console has no '${KEYBOARD%%,*}' keymap: the disk password prompt uses us (the desktop still uses $KEYBOARD)."
  fi
  # Now, before any password is typed: the disk password must be typed with the same layout here and at boot.
  loadkeys "$CONSOLE_KEYMAP" 2>/dev/null || warn "loadkeys $CONSOLE_KEYMAP failed: this console keeps its current layout."

  local dots=${ULTRON_DOTFILES-}
  if [[ -z "${ULTRON_DOTFILES+set}" ]]; then
    ask dots "Dotfiles repo (owner/repo on GitHub or a git URL; Enter for none)" ""
  fi
  if [[ "$dots" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    DOTFILES_URL="https://github.com/$dots"
  else
    DOTFILES_URL=$dots
  fi

  echo "  user $USER_NAME, computer $HOST_NAME, time zone $TIME_ZONE, keyboard $KEYBOARD (console: $CONSOLE_KEYMAP)${DOTFILES_URL:+, dotfiles $DOTFILES_URL}"
}

# ---- 3. disk ------------------------------------------------------------------

DISK="" DISK_BYTES=0

# Whole-disk device of the live medium (empty when unknown).
live_disk() {
  local src pk
  src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  [[ -n "$src" ]] || return 0
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
  if [[ -n "$pk" ]]; then printf '/dev/%s\n' "$pk"; else printf '%s\n' "$src"; fi
}

# keeps DISK: true when the disk holds a partition named in ULTRON_KEEP (label or UUID).
keeps() {
  local ids want
  [[ -n "${ULTRON_KEEP:-}" ]] || return 1
  ids=$(lsblk -J -o UUID,LABEL,PARTUUID,PARTLABEL "$1" 2>/dev/null |
    jq -r '.. | objects | (.uuid, .label, .partuuid, .partlabel) | select(. != null and . != "")' || true)
  local wants=()
  IFS=, read -ra wants <<<"$ULTRON_KEEP"
  for want in "${wants[@]}"; do
    [[ -n "$want" ]] || continue
    if grep -qixF -- "$want" <<<"$ids"; then return 0; fi
  done
  return 1
}

# parts_summary DISK: its partitions as "fstype "label" size, ..." so people recognise their disks.
parts_summary() {
  lsblk -J -o TYPE,FSTYPE,LABEL,SIZE "$1" 2>/dev/null | jq -r '
    [.blockdevices[0].children[]? |
      (.fstype // "unformatted") + (if .label then " \"" + .label + "\"" else "" end) + " " + .size] |
    if length == 0 then "no partitions" else join(", ") end' || echo "partitions unknown"
}

pick_disk() {
  say "Finding the disk to install on"
  local live names=() sizes=() models=() trans=() bytes=() parts=() hidden=() name size model tran type b
  live=$(live_disk)
  # Fields are joined with US (0x1f), not tabs, so empty MODEL/TRAN fields don't collapse.
  while IFS=$'\x1f' read -r name b model tran type; do
    [[ "$type" == disk ]] || continue
    case $name in /dev/loop* | /dev/zram* | /dev/sr*) continue ;; esac
    if [[ -n "$live" && "$name" == "$live" ]]; then
      hidden+=("$name (the USB stick this runs from)")
      continue
    fi
    if keeps "$name"; then
      hidden+=("$name (holds a partition in ULTRON_KEEP)")
      continue
    fi
    size=$(numfmt --to=iec --suffix=B "$b")
    names+=("$name") sizes+=("$size") models+=("${model:--}") trans+=("${tran:--}") bytes+=("$b")
    parts+=("$(parts_summary "$name")")
  done < <(lsblk -J -dpb -o NAME,SIZE,MODEL,TRAN,TYPE |
    jq -r '.blockdevices[] | [.name, (.size | tostring), (.model // "" | gsub("^\\s+|\\s+$"; "")), (.tran // ""), .type] | join("\u001f")')

  local h
  for h in "${hidden[@]}"; do echo "  not offered: $h"; done
  ((${#names[@]} > 0)) || die "No disk to install on was found (the USB stick and ULTRON_KEEP disks are never offered)."

  local i=-1 j
  if [[ -n "${ULTRON_DISK:-}" ]]; then
    local want
    want=$(readlink -f "$ULTRON_DISK" 2>/dev/null || printf '%s' "$ULTRON_DISK")
    for j in "${!names[@]}"; do
      if [[ "${names[$j]}" == "$want" ]]; then i=$j; fi
    done
    ((i >= 0)) || die "ULTRON_DISK=$ULTRON_DISK isn't one of the disks that can be erased: ${names[*]}"
  else
    echo "Disks that can be erased:"
    for j in "${!names[@]}"; do
      printf '  %d) %-14s %8s  %s  (%s)\n       %s\n' "$((j + 1))" "${names[$j]}" "${sizes[$j]}" "${models[$j]}" "${trans[$j]}" "${parts[$j]}"
    done
    local def="" choice
    if ((${#names[@]} == 1)); then def=1; fi
    read -rp "Install on which disk? [${def:-pick a number}] " choice
    choice=${choice:-$def}
    { [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#names[@]})); } || die "No disk picked: nothing was changed."
    i=$((choice - 1))
  fi
  DISK=${names[$i]} DISK_BYTES=${bytes[$i]}

  echo
  echo "EVERYTHING on ${DISK} (${models[$i]}, ${sizes[$i]}) will be erased:"
  echo "  ${parts[$i]}"
  local answer
  read -rp "Type wipe to continue: " answer
  [[ "$answer" == wipe ]] || die "You didn't type wipe: nothing was changed."
}

# ---- 4. passwords ---------------------------------------------------------------

DISK_PW="" USER_PW=""

# ask_twice VAR LABEL: read a non-empty password twice into VAR.
ask_twice() {
  local -n _out=$1
  local a b
  while true; do
    IFS= read -rsp "$2: " a
    echo
    IFS= read -rsp "$2 again: " b
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
  say "Passwords (keyboard layout: $CONSOLE_KEYMAP)"
  ask_twice DISK_PW "Disk password (typed at every power-on)"
  local same
  read -rp "Use the same password for your user ($USER_NAME)? [Y/n] " same
  if [[ -z "$same" || "$same" =~ ^[Yy] ]]; then
    USER_PW=$DISK_PW
  else
    ask_twice USER_PW "User password"
  fi
}

# ---- 5. config files --------------------------------------------------------------

template() {
  local here raw
  if [[ -n "${ULTRON_TMPL_URL:-}" ]]; then
    curl -fsSL "$ULTRON_TMPL_URL" || die "Couldn't download $ULTRON_TMPL_URL"
    return 0
  fi
  here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  if [[ -f "$here/install/archinstall.json.tmpl" ]]; then
    cat "$here/install/archinstall.json.tmpl"
    return 0
  fi
  [[ "$REPO_URL" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]] ||
    die "Can't derive the template URL from ULTRON_REPO=$REPO_URL: set ULTRON_TMPL_URL to the raw URL of install/archinstall.json.tmpl."
  raw="https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}/$REPO_REF/install/archinstall.json.tmpl"
  curl -fsSL "$raw" || die "Couldn't download $raw (check ULTRON_REPO and ULTRON_REF)."
}

write_configs() {
  say "Writing the archinstall configuration"
  local mib=1048576 floored root_size
  floored=$((DISK_BYTES / mib * mib))
  root_size=$((floored - ROOT_START - TAIL_GAP))
  ((root_size >= 20 * 1024 * mib)) || die "$DISK is too small (needs at least 23 GiB)."

  # umask 077 only while the config files are written: archinstall inherits the umask, and under 077
  # the new system got a 0700 /etc (logins failed with "/etc/profile: Permission denied").
  local old_umask
  old_umask=$(umask)
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

  # Passwords reach jq through its environment, never its argv (visible in ps).
  ULTRON_DISK_PW=$DISK_PW ULTRON_USER_PW=$USER_PW jq -n --arg user "$USER_NAME" '
    {encryption_password: env.ULTRON_DISK_PW,
     users: [{username: $user, "!password": env.ULTRON_USER_PW, sudo: true, groups: []}]}' >"$CREDS"
  chmod 600 "$CREDS"
  DISK_PW="" USER_PW=""
  umask "$old_umask"
  echo "Disk: $DISK, root partition: $((root_size / mib)) MiB (encrypted btrfs), ESP: 2 GiB."
}

# ---- 6. install -------------------------------------------------------------------

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
    cleanup
    cat >&2 <<EOF

archinstall failed. Its log is $INSTALL_LOG.
If it failed at the bootloader, finish by hand:
  arch-chroot /mnt
  pacman -S limine
  install -D /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
  write /boot/limine.conf with one entry:
    /Arch Linux
        protocol: linux
        path: boot():/vmlinuz-linux
        module_path: boot():/initramfs-linux.img
        cmdline: cryptdevice=PARTUUID=<PARTUUID of the 2nd partition>:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs quiet
Then reboot and continue with: git clone --branch $REPO_REF $REPO_URL ~/Projects/ultron && ~/Projects/ultron/bin/ultron install
EOF
    exit 1
  fi
}

# ---- 7. after the install -----------------------------------------------------------

# keyfile VALUE: VALUE escaped for a NetworkManager keyfile (backslashes, a leading space).
keyfile() {
  local v=${1//\\/\\\\}
  if [[ "$v" == ' '* ]]; then v="\\s${v:1}"; fi
  printf '%s' "$v"
}

# carry_wifi: give the new system the Wi-Fi network this live system is joined to, so the first boot
# is online without questions. iwd keeps what was typed in /var/lib/iwd/<name>.psk|.open|.8021x.
carry_wifi() {
  local dev ssid base psk="" uuid file
  dev=$(wifi_dev) || return 0
  ssid=$(connected_ssid "$dev")
  [[ -n "$ssid" ]] || return 0
  # iwd's file name: the SSID itself when it's only letters, digits, space, _ and -; else = and its hex.
  local plain_name='^[A-Za-z0-9_ -]+$'
  if [[ "$ssid" =~ $plain_name ]]; then
    base=/var/lib/iwd/$ssid
  else
    base=/var/lib/iwd/=$(printf '%s' "$ssid" | od -An -tx1 | tr -d ' \n')
  fi
  if [[ -f "$base.8021x" ]]; then
    warn "$ssid is an enterprise (802.1X) network: it isn't carried over. After reboot join it with: nmtui"
    return 0
  fi
  if [[ -f "$base.psk" ]]; then
    # iwd's settings files escape values the way NetworkManager's keyfiles do: copied as they are.
    psk=$(sed -n '/^Passphrase=/{s///p;q}' "$base.psk")
    [[ -n "$psk" ]] || psk=$(sed -n '/^PreSharedKey=/{s///p;q}' "$base.psk")
    if [[ -z "$psk" ]]; then
      warn "iwd kept no password for $ssid: after reboot join it with: nmtui"
      return 0
    fi
  elif [[ ! -f "$base.open" ]]; then
    warn "iwd kept no settings for $ssid: after reboot join it with: nmtui"
    return 0
  fi
  say "Carrying the Wi-Fi network $ssid over to the new system"
  uuid=$(cat /proc/sys/kernel/random/uuid)
  file="/mnt/etc/NetworkManager/system-connections/${ssid//\//_}.nmconnection"
  install -d -m 700 /mnt/etc/NetworkManager/system-connections
  install -m 600 -o root -g root /dev/null "$file" # 0600 before the password is in it
  {
    printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\n\n[wifi]\nmode=infrastructure\nssid=%s\n\n' \
      "$(keyfile "$ssid")" "$uuid" "$(keyfile "$ssid")"
    if [[ -n "$psk" ]]; then printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$psk"; fi
    printf '[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
  } >"$file"
  psk=""
}

# arm_first_boot: the first boot logs the user in on tty1 and runs `ultron install --first-boot`.
# A successful default `ultron install` removes these files with the one password-free command the sudoers
# file below allows (the install drops its sudo ticket before the last steps, so it can't ask again).
arm_first_boot() {
  say "Arming the first boot: after the disk password the install continues by itself"
  install -d /mnt/var/lib/ultron /mnt/etc/systemd/system/getty@tty1.service.d
  : >/mnt/var/lib/ultron/firstboot
  cat >/mnt/etc/systemd/system/getty@tty1.service.d/ultron-firstboot.conf <<EOF
# Written by ultron's bootstrap.sh: logs $USER_NAME in on tty1 until \`ultron install --first-boot\` is done.
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $USER_NAME %I \$TERM
EOF
  cat >/mnt/etc/sudoers.d/ultron-firstboot <<EOF
# Written by ultron's bootstrap.sh: lets a finished \`ultron install\` remove the first-boot files (and this one),
# and the first boot's password question waits for the user instead of timing out after 5 minutes.
Defaults:$USER_NAME passwd_timeout=0
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/rm -f /var/lib/ultron/firstboot /etc/systemd/system/getty@tty1.service.d/ultron-firstboot.conf /etc/profile.d/ultron-firstboot.sh /etc/sudoers.d/ultron-firstboot
EOF
  chmod 0440 /mnt/etc/sudoers.d/ultron-firstboot
  visudo -cqf /mnt/etc/sudoers.d/ultron-firstboot || die "the first-boot sudoers file is invalid"
  cat >/mnt/etc/profile.d/ultron-firstboot.sh <<'EOF'
# Written by ultron's bootstrap.sh: on the first boot, continue the install right after the login on tty1.
# Removed when `ultron install` finishes; until then every login on tty1 tries again.
if [ -e /var/lib/ultron/firstboot ] && [ "$(tty)" = /dev/tty1 ] && [ "$(id -u)" -ne 0 ] &&
  [ -x "$HOME/Projects/ultron/bin/ultron" ]; then
  "$HOME/Projects/ultron/bin/ultron" install --first-boot
fi
EOF
}

finish() {
  cleanup
  local home=/home/$USER_NAME clone="git clone --branch $REPO_REF $REPO_URL ~/Projects/ultron" cloned=0
  if ! mountpoint -q /mnt; then
    warn "nothing is mounted at /mnt; after reboot run: $clone"
  else
    say "Cloning ultron ($REPO_REF) into the new system"
    # runuser keeps root's HOME (mode 0700), whose git config the user can't read: give git the user's HOME.
    if arch-chroot /mnt runuser -u "$USER_NAME" -- env HOME="$home" \
      git -c advice.detachedHead=false clone --branch "$REPO_REF" "$REPO_URL" "$home/Projects/ultron"; then
      cloned=1
      # A tag (the ISO's ULTRON_REF) leaves a detached HEAD, which `ultron update` can't pull: put the same
      # commit on a local branch that follows the repo's default branch.
      # shellcheck disable=SC2016 # expanded by the inner sh
      arch-chroot /mnt runuser -u "$USER_NAME" -- env HOME="$home" sh -c 'cd "$1" || exit 1
        git symbolic-ref -q HEAD >/dev/null && exit 0
        up=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) &&
          git switch -q -c "${up#origin/}" && git branch -q -u "$up"' sh "$home/Projects/ultron" ||
        warn "couldn't put the ultron checkout on a branch: ultron update won't pull until you run: git -C ~/Projects/ultron switch main"
    else
      warn "the clone failed; after reboot run: $clone"
    fi

    say "Writing ~/.config/ultron/ultron.conf"
    mkdir -p "/mnt$home/.config/ultron"
    {
      printf '# Machine settings (ultron conf set KEY VALUE). Written by bootstrap.sh.\n'
      printf 'KEYBOARD=%s\n' "$KEYBOARD"
      if [[ -n "$DOTFILES_URL" ]]; then printf 'DOTFILES_REPO=%s\n' "$DOTFILES_URL"; fi
    } >"/mnt$home/.config/ultron/ultron.conf"
    arch-chroot /mnt chown -R "$USER_NAME:" "$home/.config" || warn "couldn't give $home/.config to $USER_NAME"

    carry_wifi
    if ((cloned)); then
      arm_first_boot
      printf 'If the install did not continue by itself, run: ~/Projects/ultron/bin/ultron install --first-boot\n' >/mnt/etc/motd
    else
      printf 'Next: run %s && ~/Projects/ultron/bin/ultron install --first-boot\n' "$clone" >/mnt/etc/motd
    fi
    printf 'KEYMAP=%s\nFONT=default8x16\n' "$CONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
    if [[ "$CONSOLE_KEYMAP" != us ]]; then
      # The initramfs asks for the disk password; it copies the keymap from vconsole.conf when it's built.
      say "Rebuilding the initramfs with the $CONSOLE_KEYMAP keymap (for the disk password prompt)"
      arch-chroot /mnt mkinitcpio -P ||
        warn "mkinitcpio failed: the disk password prompt may use the us layout until the next kernel update"
    fi
  fi
  echo
  say "Done. Remove the USB stick and reboot (type: reboot). Type the disk password: the install continues by itself, asks for your password once, and reboots into the desktop."
}

main() {
  checks
  settings
  pick_disk
  passwords
  write_configs
  run_archinstall
  finish
}

main "$@"
