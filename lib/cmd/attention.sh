# shellcheck shell=bash
# ultron attention: who needs the user, and getting them there.
#   attention                 go to the window that needs you, else the latest urgent window
#   attention --raise TITLE   an agent needs the user (any agent's hook can call this)
#   attention --done TITLE    an agent finished something (phone push only while away)
#   attention --away          swayidle: mark the user away; one digest push if something waits
# Arguments after TITLE are ignored: some agents append their own event data to the hook command.
#
# $R/needs-you holds three lines: time, title, the workspace to go to. It exists while something
# waits; attentiond removes it when the user arrives on that workspace.

# _caller_window: sway id of the window this process runs in (its terminal), empty when there is none.
_caller_window() {
  local -A win=()
  local wpid wid pid=$PPID stat
  while read -r wpid wid; do
    win[$wpid]=$wid
  done < <(swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.pid? != null and .pid > 0) | "\(.pid) \(.id)"' 2>/dev/null)
  ((${#win[@]})) || return 0
  while ((pid > 1)); do
    if [[ -n "${win[$pid]-}" ]]; then
      printf '%s\n' "${win[$pid]}"
      return 0
    fi
    # The parent's pid is the 2nd field after the ")" that closes the command name.
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 0
    stat=${stat##*) }
    read -r _ pid _ <<<"$stat"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  done
}

# _con_ws CON_ID: name of the workspace holding that window (empty when it is gone).
_con_ws() {
  swaymsg -t get_tree 2>/dev/null |
    jq -r --argjson id "$1" 'first(.. | objects | select(.type? == "workspace") | select(any(.. | objects; .id == $id)) | .name) // ""' 2>/dev/null || true
}

# attention_raise TITLE [CON_ID]: the window CON_ID (default: the boss window) needs the user.
# Away -> phone; already on its workspace -> mark it; focus mode -> mark it; else jump there after
# the typing guard. The caller shows its own desktop notification.
attention_raise() {
  local title=${1:-An agent needs you} con=${2:-} ws="" ultron="$ULTRON_ROOT/bin/ultron"
  ensure_rundir
  if [[ -z "$con" ]]; then con=$(sway_ids '(.app_id // "") == "ultron-boss"' 2>/dev/null | tail -n1) || true; fi
  if [[ -n "$con" ]]; then ws=$(_con_ws "$con"); fi
  if [[ -z "$ws" ]]; then con=""; fi
  printf '%s\n%s\n%s\n' "$(date -Iseconds)" "$title" "${ws:-${WS[1]}}" >"$R/needs-you"

  if is_away; then
    "$ultron" notify --phone --urgent "An agent needs you" "$title" || true
  elif [[ -z "$con" ]]; then
    : # no window to go to: the flag and the caller's notification are all there is
  elif [[ $(focused_ws 2>/dev/null) == "$ws" ]]; then
    # Already there: no workspace change will come to clear the flag.
    rm -f "$R/needs-you"
    swaymsg "[con_id=$con] urgent enable" >/dev/null 2>&1 || true
  elif [[ -e "$R/focus" ]]; then
    swaymsg "[con_id=$con] urgent enable" >/dev/null 2>&1 || true
  else
    detach "$ultron" jump "${ws%%:*}" --con-id "$con"
  fi
}

attention_done() {
  local title=${1:-An agent finished}
  if is_away; then
    "$ULTRON_ROOT/bin/ultron" notify --phone "Finished" "$title" || true
  fi
}

# attention_arrived WORKSPACE: the user is now on WORKSPACE; clear the flag if that is where they were needed.
attention_arrived() {
  local want=""
  [[ -e "$R/needs-you" ]] || return 0
  { read -r _ && read -r _ && read -r want; } <"$R/needs-you" || true
  if [[ -z "$want" || "$want" == "$1" ]]; then rm -f "$R/needs-you"; fi
}

cmd_attention() {
  ensure_rundir
  case ${1:-} in
  --raise)
    is_away || desktop_notify "An agent needs you" "${2:-}"
    attention_raise "${2:-}" "$(_caller_window)"
    ;;
  --done)
    is_away || desktop_notify "Finished" "${2:-An agent finished}"
    attention_done "${2:-}"
    ;;
  --away)
    touch "$R/away"
    if [[ -s "$R/needs-you" ]]; then
      local title
      title=$(sed -n 2p "$R/needs-you")
      # Detached: swayidle waits for this command, and a slow push would make it miss the resume.
      detach "$ULTRON_ROOT/bin/ultron" notify --phone --urgent "An agent needs you" "${title:-a question is waiting}"
    fi
    ;;
  "")
    local want=""
    if [[ -e "$R/needs-you" ]]; then
      { read -r _ && read -r _ && read -r want; } <"$R/needs-you" || true
    fi
    if [[ -e "$R/needs-you" && ("$want" == "${WS[1]}" || -z "$want") ]]; then
      # shellcheck source=boss.sh
      source "$ULTRON_ROOT/lib/cmd/boss.sh"
      cmd_boss
    elif [[ -n "$want" ]]; then
      goto_ws "$want"
      swaymsg '[urgent=latest] focus' >/dev/null 2>&1 || true
    elif ! swaymsg '[urgent=latest] focus' >/dev/null 2>&1; then
      desktop_notify "Nothing needs you" ""
    fi
    ;;
  *) die "usage: ultron attention [--raise TITLE | --done TITLE | --away]" ;;
  esac
}
