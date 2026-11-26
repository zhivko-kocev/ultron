# shellcheck shell=bash
# ultron snap: region screenshot for the boss. Saves it, copies its path, takes you to the boss.

cmd_snap() {
  local dir="$HOME/Pictures/Screenshots" geom file
  mkdir -p "$dir"
  geom=$(slurp) || return 0
  file="$dir/boss-$(date +%Y%m%d-%H%M%S).png"
  grim -g "$geom" "$file"
  printf '%s' "$file" | wl-copy
  source "$ULTRON_ROOT/lib/cmd/boss.sh"
  cmd_boss
  desktop_notify "Path copied" "Paste it into the boss with Ctrl+Shift+V"
}
