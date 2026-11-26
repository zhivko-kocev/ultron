# shellcheck shell=bash
# ultron attentiond: the attention daemon (systemd --user). It clears the "needs you" flag when you
# reach the workspace that wanted you and, when the boss is Jocasta, turns Jocasta's notifications into
# `ultron attention --raise/--done`. Any watcher ending ends the service; systemd restarts it.

# shellcheck source=attention.sh
source "$ULTRON_ROOT/lib/cmd/attention.sh"

cmd_attentiond() {
  ensure_rundir
  local pids=() rc=0 log
  _attn_workspaces &
  pids+=($!)
  # Jocasta may become the boss later (`ultron install jocasta`): its log is followed either way,
  # and tail -F simply waits while the file doesn't exist.
  log="$(jocasta_data_dir)/notifications.jsonl"
  _attn_jocasta_log "$log" &
  pids+=($!)
  _attn_jocasta_questions &
  pids+=($!)
  say "watching sway workspaces, $log and Jocasta's questions"
  wait -n "${pids[@]}" || rc=$?
  kill "${pids[@]}" 2>/dev/null || true
  die "a watcher stopped (exit $rc)"
}

_attn_workspaces() {
  local name
  # swaymsg may pretty-print each event over several lines; jq reads the stream either way.
  swaymsg -t subscribe -m '["workspace"]' |
    jq -r --unbuffered 'select(.change == "focus") | .current.name // ""' |
    while IFS= read -r name; do
      attention_arrived "$name"
    done
}

# Jocasta writes one JSON line per notification: reason is blocked, done, failed or event.
_attn_jocasta_log() {
  local line reason title result f
  tail -n0 -F "$1" 2>/dev/null | while IFS= read -r line; do
    mapfile -t f < <(jq -r '(.reason // ""), (.title // "" | gsub("[\n\t]"; " ")), (.result // "")' <<<"$line" 2>/dev/null)
    ((${#f[@]} == 3)) || continue
    reason=${f[0]} title=${f[1]} result=${f[2]}
    [[ $result == repeat ]] && continue
    case $reason in
    blocked) attention_raise "$title" ;;
    done | failed) attention_done "Thread $reason: $title" ;;
    esac
  done
}

# Jocasta's Allow and service questions go straight to notify-send ("Jocasta asks") without a
# notifications.jsonl line (jocasta#4), so they are read off the session bus.
# Notify's string arguments arrive in order: app_name, app_icon, summary, body.
_attn_jocasta_questions() {
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
          attention_raise "${body:-a question is waiting}"
        fi
        continue
        ;;
      esac
      n=$((n + 1))
    done
}
