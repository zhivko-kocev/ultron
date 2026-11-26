# shellcheck shell=bash
# ultron attentiond: follows Jocasta's notifications.jsonl and sway's workspace events (run by systemd --user).
# Either loop ending ends the service; systemd restarts it.

cmd_attentiond() {
  ensure_rundir
  local log
  log="$(jocasta_data_dir)/notifications.jsonl"
  say "following $log"
  _attn_notifications "$log" &
  local p1=$!
  _attn_workspaces &
  local p2=$!
  local rc=0
  wait -n "$p1" "$p2" || rc=$?
  kill "$p1" "$p2" 2>/dev/null || true
  die "a watcher stopped (exit $rc)"
}

_attn_notifications() {
  local line reason title result f ultron="$ULTRON_ROOT/bin/ultron"
  # tail -F waits for the file when Jocasta has not written it yet.
  tail -n0 -F "$1" 2>/dev/null | while IFS= read -r line; do
    mapfile -t f < <(jq -r '(.reason // ""), (.title // "" | gsub("[\n\t]"; " ")), (.result // "")' <<<"$line" 2>/dev/null)
    ((${#f[@]} == 3)) || continue
    reason=${f[0]} title=${f[1]} result=${f[2]}
    [[ $result == repeat ]] && continue
    case $reason in
    blocked)
      printf '%s\n%s\n' "$(date -Iseconds)" "$title" >"$R/needs-you"
      if is_away; then
        "$ultron" notify --phone --urgent "Jocasta needs you" "$title" || true
      elif [[ -e "$R/focus" ]]; then
        swaymsg '[app_id="^ultron-boss$"] urgent enable' >/dev/null 2>&1 || true
      else
        # Already on 1:boss produces no workspace event, so clear the flag once the jump lands there.
        (
          "$ultron" jump 1 --app-id ultron-boss || true
          [[ $(focused_ws 2>/dev/null) == "${WS[1]}" ]] && rm -f "$R/needs-you"
        ) &
      fi
      ;;
    done | failed)
      is_away && { "$ultron" notify --phone "Jocasta: thread $reason" "$title" || true; }
      ;;
    esac
  done
}

_attn_workspaces() {
  local ev
  swaymsg -t subscribe -m '["workspace"]' | while IFS= read -r ev; do
    if [[ $(jq -r 'select(.change == "focus") | .current.name // ""' <<<"$ev" 2>/dev/null) == "${WS[1]}" ]]; then
      rm -f "$R/needs-you"
    fi
  done
}
