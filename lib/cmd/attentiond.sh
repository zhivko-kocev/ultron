# shellcheck shell=bash
# ultron attentiond: the attention daemon (systemd --user). It follows sway: a focused window answers its
# attention request; reaching a workspace clears its "new" mark, drops requests of closed windows and closes
# tagged windows whose folder is gone; an agent's visible browser window goes to workspace 3. When the boss is
# Jocasta it turns Jocasta's notifications into attention requests. Any watcher ending ends the service;
# systemd restarts it.

# shellcheck source=attention.sh
source "$ULTRON_ROOT/lib/cmd/attention.sh"
# shellcheck source=show.sh
source "$ULTRON_ROOT/lib/cmd/show.sh"

cmd_attentiond() {
  ensure_rundir
  local pids=() rc=0 log
  _attn_sway &
  pids+=($!)
  # Jocasta may become the boss later (`ultron install jocasta`): its log is followed either way,
  # and tail -F simply waits while the file doesn't exist.
  log="$(jocasta_data_dir)/notifications.jsonl"
  _attn_jocasta_log "$log" &
  pids+=($!)
  _attn_jocasta_questions &
  pids+=($!)
  say "watching sway, $log and Jocasta's questions"
  wait -n "${pids[@]}" || rc=$?
  kill "${pids[@]}" 2>/dev/null || true
  die "a watcher stopped (exit $rc)"
}

_attn_sway() {
  local kind a b
  # swaymsg may pretty-print each event over several lines; jq reads the stream either way.
  swaymsg -t subscribe -m '["workspace","window"]' |
    jq -r --unbuffered '
      if has("container") then
        if .change == "focus" then "focus\t\(.container.id)"
        elif .change == "new" then "new\t\(.container.id)\t\(.container.pid // 0)"
        else empty end
      elif .change == "focus" then "ws\t\(.current.name // "")"
      else empty end' |
    while IFS=$'\t' read -r kind a b; do
      _attn_event "$kind" "$a" "${b:-}" || true
    done
}

# _attn_event focus CON | ws NAME | new CON PID
_attn_event() {
  case $1 in
  focus) attention_seen "$2" ;;
  ws) show_locked _attn_ws_focus "$2" ;;
  new) if _attn_agent_browser "$3"; then show_locked _attn_agent_window "$2"; fi ;;
  esac
}

# _attn_ws_focus NAME: the user is on workspace NAME.
_attn_ws_focus() {
  local alive f
  show_unmark "${1%%:*}"
  alive=$(sway_ids true 2>/dev/null) || return 0
  alive=" ${alive//$'\n'/ } "
  for f in "$_ATTN_DIR"/*; do
    [[ -f "$f" && "$alive" != *" ${f##*/} "* ]] || continue
    rm -f "$f"
  done
  show_sweep "$alive"
}

# _attn_agent_browser PID: 0 when PID is a browser an agent drives (remote debugging on, not the preview profile).
_attn_agent_browser() {
  local pid=$1 args=()
  [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1)) || return 1
  mapfile -d '' args 2>/dev/null <"/proc/$pid/cmdline" || return 1
  [[ "${args[*]}" == *--remote-debugging* && "${args[*]}" != *"$PREVIEW_PROFILE"* ]]
}

# _attn_agent_window CON: an agent's browser showed a window: it goes to workspace 3 like the windows `show` opens.
_attn_agent_window() {
  _show_move "$1" 3 || return 0
  show_reg_add "$1" "agent-web:$1" - -
  show_mark 3 "$1"
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
