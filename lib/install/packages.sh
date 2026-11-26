# shellcheck shell=bash
# step packages: the official package lists (ai.txt only with LOCAL_AI=yes); updates the system too.

step_packages() {
  local d=$ULTRON_ROOT/packages lists=() pkgs=() local_ai
  lists=("$d"/{base,desktop,apps,containers}.txt)
  conf_var local_ai LOCAL_AI
  if [[ "$local_ai" == yes ]]; then lists+=("$d/ai.txt"); fi
  mapfile -t pkgs < <(list_packages "${lists[@]}")
  say "Installing ${#pkgs[@]} packages with pacman (and updating the system)"
  pacman_install -yu "${pkgs[@]}" || die "pacman failed: read the error above, fix it, then rerun: ultron install packages"
}
