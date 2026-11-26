# shellcheck shell=bash
# ultron toggle awake|nightlight|record: switches in the menu (Toggle ▸, Capture ▸).
#   awake       stay awake: no away state, screen lock or screen off until it is switched off (bar: AWAKE)
#   nightlight  warmer colours (gammastep, 4000 K) until switched off
#   record      record a region of the screen to ~/Videos (bar: REC); again to stop

_toggle_awake() {
  if [[ -e "$R/awake" ]]; then
    rm -f "$R/awake"
    desktop_notify "Stay awake off" "The screen locks and turns off on its own again"
  else
    touch "$R/awake"
    desktop_notify "Stay awake on" "No screen lock or screen off until you switch it off (menu: Toggle)"
  fi
  detach "$ULTRON_ROOT/bin/ultron" idle
}

_toggle_nightlight() {
  if pgrep -x gammastep >/dev/null 2>&1; then
    pkill -x gammastep || true
    desktop_notify "Night light off" ""
  else
    have gammastep || die "gammastep is missing: run 'ultron install packages'"
    detach gammastep -P -O 4000
    desktop_notify "Night light on" "Warmer colours until you switch it off (menu: Toggle)"
  fi
}

_toggle_record() {
  local geom file
  if pgrep -x wf-recorder >/dev/null 2>&1; then
    file=$(cat "$R/recording" 2>/dev/null || true)
    pkill -INT -x wf-recorder || true
    rm -f "$R/recording"
    desktop_notify "Recording saved" "${file:-~/Videos}"
    return 0
  fi
  have wf-recorder || die "wf-recorder is missing: run 'ultron install packages'"
  geom=$(slurp) || {
    rm -f "$R/recording"
    return 0
  }
  mkdir -p "$HOME/Videos"
  file="$HOME/Videos/recording-$(date +%F-%H%M%S).mp4"
  printf '%s\n' "$file" >"$R/recording"
  detach wf-recorder -g "$geom" -f "$file"
  desktop_notify "Recording" "Stop it with the menu (Capture ▸ Stop recording) or: ultron toggle record"
}

cmd_toggle() {
  ensure_rundir
  case ${1:-} in
  awake) _toggle_awake ;;
  nightlight) _toggle_nightlight ;;
  record) _toggle_record ;;
  *) die "usage: ultron toggle awake|nightlight|record" ;;
  esac
}
