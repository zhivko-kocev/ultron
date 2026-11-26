# shellcheck shell=bash
# ultron clip: pick from the clipboard history.

cmd_clip() {
  local sel
  sel=$(cliphist list | fuzzel --dmenu --prompt "clip ▸ ") || return 0
  printf '%s' "$sel" | cliphist decode | wl-copy
}
