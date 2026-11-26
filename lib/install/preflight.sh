# shellcheck shell=bash
# step preflight: refuse to run unless this is the user's own Arch install, booted UEFI, online.

step_preflight() {
  ((EUID != 0)) || die "Run this as your user, not root."
  [[ -f /etc/arch-release ]] || die "This isn't Arch Linux: ultron only installs on Arch."
  is_uefi || die "This system didn't boot in UEFI mode: ultron needs UEFI (turn off CSM/legacy boot in the firmware settings)."
  if ! curl -fsI --max-time 10 https://archlinux.org >/dev/null 2>&1; then
    if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
      die "No internet connection. Run nmtui, pick 'Activate a connection', join your Wi-Fi, then run this again."
    fi
    die "No internet connection: plug in a network cable (or fix the connection), then run this again."
  fi
  local root home
  root=$(readlink -f "$ULTRON_ROOT")
  home=$(readlink -f "$HOME")
  [[ "$root" == "$home"/* ]] ||
    die "The ultron checkout ($root) must be inside your home folder: its desktop files are linked from there. Clone it again: git clone $(ultron_repo_url) ~/Projects/ultron"
  mkdir -p "$ULTRON_CONF_DIR"/{conf.d,sway,themes,hooks}
  ok "Arch, UEFI, online, checkout at $root"
}
