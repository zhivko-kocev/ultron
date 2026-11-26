# shellcheck shell=bash
# ultron attentiond: follows Jocasta's notifications.jsonl, Jocasta's question notifications and sway's
# workspace events (run by systemd --user). Any watcher ending ends the service; systemd restarts it.

cmd_attentiond() {
  ensure_rundir
  local log
  log="$(jocasta_data_dir)/notifications.jsonl"
  say "following $log, Jocasta's questions and sway workspaces"
  _attn_notifications "$log" &
  local p1=$!
  _attn_questions &
  local p2=$!
  _attn_workspaces &
  local p3=$!
  local rc=0
  wait -n "$p1" "$p2" "$p3" || rc=$?
  kill "$p1" "$p2" "$p3" 2>/dev/null || true
  die "a watcher stopped (exit $rc)"
}

# _attn_blocked TITLE: Jocasta needs the user. Away: phone; focus mode: urgent mark; else jump to the boss.
_attn_blocked() {
  local title=$1 ultron="$ULTRON_ROOT/bin/ultron"
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
}

_attn_notifications() {
  local line reason title result f
  # tail -F waits for the file when Jocasta has not written it yet.
  tail -n0 -F "$1" 2>/dev/null | while IFS= read -r line; do
    mapfile -t f < <(jq -r '(.reason // ""), (.title // "" | gsub("[\n\t]"; " ")), (.result // "")' <<<"$line" 2>/dev/null)
    ((${#f[@]} == 3)) || continue
    reason=${f[0]} title=${f[1]} result=${f[2]}
    [[ $result == repeat ]] && continue
    case $reason in
    blocked) _attn_blocked "$title" ;;
    done | failed)
      is_away && { "$ULTRON_ROOT/bin/ultron" notify --phone "Jocasta: thread $reason" "$title" || true; }
      ;;
    esac
  done
}

# Jocasta's Allow and service questions go straight to notify-send ("Jocasta asks") without a
# notifications.jsonl line (review item R11), so they are read off the session bus.
# Notify's string arguments arrive in order: app_name, app_icon, summary, body.
_attn_questions() {
  local line n=-1 app="" summary="" body="" s
  dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" |
    while IFS= read -r line; do
      if [[ $line == *"member=Notify"* ]]; then
        n=0 app="" summary="" body=""
        continue
      fi
      ((n >= 0)) || continue
      [[ $line =~ ^[[:space:]]+string\ \"(.*)$ ]] || continue
      s=${BASH_REMATCH[1]%\"}
      case $n in
      0) app=$s ;;
      2) summary=$s ;;
      3)
        body=$s
        n=-1
        if [[ $app == Jocasta && $summary == "Jocasta asks" ]]; then
          _attn_blocked "${body:-a question is waiting}"
        fi
        continue
        ;;
      esac
      n=$((n + 1))
    done
}

_attn_workspaces() {
  local name
  # swaymsg may pretty-print each event over several lines; jq reads the stream either way.
  swaymsg -t subscribe -m '["workspace"]' |
    jq -r --unbuffered 'select(.change == "focus") | .current.name // ""' |
    while IFS= read -r name; do
      [[ $name == "${WS[1]}" ]] && rm -f "$R/needs-you"
    done
}
