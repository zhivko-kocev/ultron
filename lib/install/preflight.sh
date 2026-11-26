# shellcheck shell=bash
# step preflight: refuse to run unless this is the user's own Arch install, booted UEFI, online.

step_preflight() {
  ((EUID != 0)) || die "Run this as your user, not root."
  [[ -f /etc/arch-release ]] || die "This isn't Arch Linux: ultron only installs on Arch."
  is_uefi || die "This system didn't boot in UEFI mode: ultron needs UEFI (see docs/bios.md)."
  curl -fsI https://archlinux.org >/dev/null 2>&1 || die "No internet connection: connect, then run this again."
  local want here
  want=$(readlink -f "$HOME/Projects/ultron" 2>/dev/null || true)
  here=$(readlink -f "$ULTRON_ROOT")
  [[ -n "$want" && "$want" == "$here" ]] ||
    die "The ultron repo must live at ~/Projects/ultron (it's at $here). Clone it there: git clone $ULTRON_REPO_URL ~/Projects/ultron"
  # sudo is refreshed in the background by `ultron install` (sudo_keepalive).
  sudo -v || die "sudo failed: your user needs sudo rights."
  ok "Arch, UEFI, online, repo at ~/Projects/ultron, sudo works"
}
