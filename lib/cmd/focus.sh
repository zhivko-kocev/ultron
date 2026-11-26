# shellcheck shell=bash
# ultron focus [toggle|on|off]: focus mode. No jumps (a window that needs you gets an urgent mark instead) and
# notifications are held (mako's do-not-disturb mode) until it ends.

cmd_focus() {
  local mode=${1:-toggle}
  ensure_rundir
  if [[ $mode == toggle ]]; then
    if [[ -e "$R/focus" ]]; then mode=off; else mode=on; fi
  fi
  case $mode in
  on)
    touch "$R/focus"
    desktop_notify "Focus mode on" "No jumps and no notifications: a workspace turns red when an agent needs you"
    makoctl mode -a do-not-disturb >/dev/null 2>&1 || true
    ;;
  off)
    rm -f "$R/focus"
    makoctl mode -r do-not-disturb >/dev/null 2>&1 || true
    desktop_notify "Focus mode off" "Jumps and notifications are back on"
    ;;
  *) die "usage: ultron focus [toggle|on|off]" ;;
  esac
}
