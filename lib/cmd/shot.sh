# shellcheck shell=bash
# ultron shot region|full: region into swappy, or the full screen to a file and the clipboard.

cmd_shot() {
  local dir="$HOME/Pictures/Screenshots" geom file
  mkdir -p "$dir"
  case ${1:-} in
  region)
    geom=$(slurp) || return 0
    grim -g "$geom" - | swappy -f -
    ;;
  full)
    file="$dir/$(date +%Y-%m-%d_%H%M%S).png"
    grim "$file"
    wl-copy --type image/png <"$file"
    desktop_notify "Screenshot saved" "$file (also copied)"
    ;;
  *) die "usage: ultron shot region|full" ;;
  esac
}
