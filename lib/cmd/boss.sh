# shellcheck shell=bash
# ultron boss [--start]: make sure the boss window exists; without --start, take the user to it.
# The boss is whatever the BOSS setting names (omp, jocasta, claude, codex, ...). Its sudo goes
# through ultron's popup because agent-bin is first on its PATH.

cmd_boss() {
  local start=0
  case ${1:-} in
  --start) start=1 ;;
  "") ;;
  *) die "usage: ultron boss [--start]" ;;
  esac

  local cmd=() id fresh=0
  read -ra cmd <<<"$(boss_kind)"
  id=$(sway_ids '(.app_id // "") == "ultron-boss"' | tail -n1)
  if [[ -z "$id" ]]; then
    have "${cmd[0]}" || die "the boss '${cmd[0]}' isn't installed. Pick another: ultron conf set BOSS <command> (or the menu: Setup > Boss agent)"
    detach foot --app-id=ultron-boss --title=boss -- env PATH="$AGENT_BIN:$PATH" "${cmd[@]}"
    id=$(wait_window '^ultron-boss$' 10) || die "the boss window did not appear within 10 s"
    fresh=1
  fi
  if ((start)); then return 0; fi

  ensure_rundir
  local cur
  cur=$(focused_ws)
  if [[ "$cur" != "${WS[1]}" ]]; then printf '%s\n' "$cur" >"$R/back"; fi
  swaymsg "workspace \"${WS[1]}\"; [con_id=$id] focus" >/dev/null
  if [[ ${cmd[0]} == jocasta ]]; then
    if ((fresh)); then sleep 1; else sleep 0.1; fi
    # Alt+1: Jocasta's boss row.
    wtype -M alt 1 -m alt
  fi
}
