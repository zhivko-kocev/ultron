# shellcheck shell=bash
# ultron jump N [--con-id C | --app-id A]: move the user to workspace N, after the typing guard.

cmd_jump() {
  local n=${1:-}
  [[ -n "$n" ]] || die "usage: ultron jump N [--con-id C | --app-id A]"
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
    --app-id)
      [[ -n "${2:-}" ]] || die "--app-id needs a value"
      crit="[app_id=\"^${2}\$\"]"
      shift 2
      ;;
    *) die "jump: unknown option '$1'" ;;
    esac
  done
  ensure_rundir

  if [[ -e "$R/focus" ]]; then
    [[ -n "$crit" ]] && swaymsg "$crit urgent enable" >/dev/null 2>&1 || true
    return 0
  fi

  # One pending jump at a time; later ones queue behind it.
  exec 9>"$R/jump.lock"
  flock -w 120 9 || die "another jump is still pending"

  if ! wait_idle 60; then
    [[ -n "$crit" ]] && swaymsg "$crit urgent enable" >/dev/null 2>&1 || true
    desktop_notify -u critical "Workspace $ws wants you" "Press Super+A to go there"
    return 0
  fi

  local cur
  cur=$(focused_ws)
  [[ "$cur" != "$ws" ]] && printf '%s\n' "$cur" >"$R/back"
  swaymsg "workspace \"$ws\"" >/dev/null
  [[ -n "$crit" ]] && swaymsg "$crit focus" >/dev/null 2>&1 || true
}
