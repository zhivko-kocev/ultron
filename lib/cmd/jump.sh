# shellcheck shell=bash
# ultron jump N [--con-id C]: move the user to workspace N, after the typing guard.

cmd_jump() {
  local n=${1:-}
  [[ -n "$n" ]] || die "usage: ultron jump N [--con-id C]"
  shift
  local ws crit=""
  ws=$(ws_name "$n")
  while (($#)); do
    case $1 in
    --con-id)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--con-id needs a number"
      crit="[con_id=$2]"
      shift 2
      ;;
    *) die "jump: unknown option '$1'" ;;
    esac
  done
  ensure_rundir

  if [[ -e "$R/focus" ]]; then
    if [[ -n "$crit" ]]; then swaymsg "$crit urgent enable" >/dev/null 2>&1 || true; fi
    return 0
  fi

  # One pending jump at a time; later ones queue behind it.
  exec 9>"$R/jump.lock"
  flock -w 120 9 || die "another jump is still pending"

  if ! wait_idle 60; then
    if [[ -n "$crit" ]]; then swaymsg "$crit urgent enable" >/dev/null 2>&1 || true; fi
    desktop_notify -u critical "Workspace $ws wants you" "Press Super+A to go there"
    return 0
  fi
  # Focus mode may have been switched on while this jump waited.
  if [[ -e "$R/focus" ]]; then
    if [[ -n "$crit" ]]; then swaymsg "$crit urgent enable" >/dev/null 2>&1 || true; fi
    return 0
  fi

  goto_ws "$ws"
  if [[ -n "$crit" ]]; then swaymsg "$crit focus" >/dev/null 2>&1 || true; fi
}
