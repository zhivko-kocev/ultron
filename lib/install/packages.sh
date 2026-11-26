# shellcheck shell=bash
# step packages: every official package from packages/*.txt (all lists except aur.txt).

step_packages() {
  local d=$ULTRON_ROOT/packages pkgs=()
  mapfile -t pkgs < <(list_packages "$d"/{base,desktop,apps,dev,containers,ai}.txt)
  say "Installing ${#pkgs[@]} packages with pacman (and updating the system)"
  sudo pacman -Syu --needed --noconfirm "${pkgs[@]}" || die "pacman failed: read the error above, fix it, then rerun: ultron install packages"
}
