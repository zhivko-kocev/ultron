# shellcheck shell=bash
# ultron focus [toggle|on|off]: focus mode. No jumps; the boss window gets an urgent mark instead.

cmd_focus() {
  local mode=${1:-toggle}
  ensure_rundir
  if [[ $mode == toggle ]]; then
    if [[ -e "$R/focus" ]]; then mode=off; else mode=on; fi
  fi
  case $mode in
  on)
    touch "$R/focus"
    desktop_notify "Focus mode on" "No jumps: workspace 1 turns red when the boss needs you"
    ;;
  off)
    rm -f "$R/focus"
    desktop_notify "Focus mode off" "Jumps are back on"
    ;;
  *) die "usage: ultron focus [toggle|on|off]" ;;
  esac
}
