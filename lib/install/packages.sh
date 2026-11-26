# shellcheck shell=bash
# step packages: the official package lists (ai.txt only when local AI is on: local_ai_on); updates the system too.

step_packages() {
  local d=$ULTRON_ROOT/packages lists=() pkgs=()
  lists=("$d"/{base,desktop,apps,containers}.txt)
  if local_ai_on; then lists+=("$d/ai.txt"); fi
  mapfile -t pkgs < <(list_packages "${lists[@]}")
  # SwayFX (the desktop step's Effects) replaces sway: asking pacman for sway would remove it again.
  if pacman -Q swayfx >/dev/null 2>&1; then
    local i
    for i in "${!pkgs[@]}"; do
      if [[ "${pkgs[$i]}" == sway ]]; then unset 'pkgs[i]'; fi
    done
  fi
  say "Installing ${#pkgs[@]} packages with pacman (and updating the system)"
  pacman_install -yu "${pkgs[@]}" || die "pacman failed: read the error above, fix it, then rerun: ultron install packages"
}
