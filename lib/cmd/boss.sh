# shellcheck shell=bash
# ultron boss [--start]: make sure the boss window exists; without --start, take the user to it.

cmd_boss() {
  local start=0
  case ${1:-} in
  --start) start=1 ;;
  "") ;;
  *) die "usage: ultron boss [--start]" ;;
  esac

  local kind id fresh=0
  kind=$(boss_kind)
  id=$(sway_ids '(.app_id // "") == "ultron-boss"' | tail -n1)
  if [[ -z "$id" ]]; then
    have "$kind" || die "boss '$kind' is not installed (BOSS in $ULTRON_CONF)"
    detach foot --app-id=ultron-boss --title=boss -- env PATH="$AGENT_BIN:$PATH" "$kind"
    id=$(wait_window '^ultron-boss$' 10) || die "the boss window did not appear within 10 s"
    fresh=1
  fi
  ((start)) && return 0

  ensure_rundir
  local cur
  cur=$(focused_ws)
  [[ "$cur" != "${WS[1]}" ]] && printf '%s\n' "$cur" >"$R/back"
  swaymsg "workspace \"${WS[1]}\"; [con_id=$id] focus" >/dev/null
  if [[ $kind == jocasta ]]; then
    if ((fresh)); then sleep 1; else sleep 0.1; fi
    # Alt+1: Jocasta's boss row.
    wtype -M alt 1 -m alt
  fi
}
