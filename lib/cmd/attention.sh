# shellcheck shell=bash
# ultron attention: who needs the user, and getting them there.
#   attention                 go to the oldest window that needs you, else the newest window shown to you on a
#                             workspace still marked new, else the first marked workspace
#   attention --raise TITLE   an agent needs the user (any agent's hook can call this)
#   attention --done TITLE    an agent finished something (phone push only while away)
#   attention --list          the queue, oldest first: TIME<TAB>WORKSPACE<TAB>TITLE
#   attention --away          swayidle: mark the user away; one digest push if something waits
# Arguments after TITLE are ignored: some agents append their own event data to the hook command.
#
# The queue is $R/attention/<con_id>, one file per waiting window with three lines: the time of the first
# request, the latest title, the workspace; a fourth holds the id of its desktop notification when it has one.
# attentiond removes a file when its window gets focus, and the notification goes with it. Entries change only
# under the lock $R/attention.lock. Only a request moves the user (through `jump`); windows shown with
# `ultron show` only mark the bar.

_ATTN_DIR="$R/attention"

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

# _con_focused CON_ID: 0 when that window has the keyboard focus.
_con_focused() {
  [[ $(swaymsg -t get_tree 2>/dev/null | jq -r --argjson id "$1" 'any(.. | objects; .id? == $id and .focused == true)' 2>/dev/null) == true ]]
}

# attention_list: TIME<TAB>WORKSPACE<TAB>TITLE<TAB>CON_ID per waiting window, oldest first.
attention_list() {
  local f time title ws
  for f in "$_ATTN_DIR"/*; do
    [[ -f "$f" ]] || continue
    { read -r time && read -r title && read -r ws; } <"$f" || continue
    printf '%s\t%s\t%s\t%s\n' "$time" "$ws" "$title" "${f##*/}"
  done | sort -t $'\t' -k1,1 -k4,4n
}

# _attn_oldest: con id of the oldest waiting window, empty when nothing waits.
_attn_oldest() {
  local _t _w _ti con=""
  IFS=$'\t' read -r _t _w _ti con < <(attention_list) || true
  printf '%s\n' "$con"
}

# attention_seen CON_ID: the user reached that window; its request is answered and its notification dismissed.
attention_seen() {
  local l=()
  {
    flock 6
    mapfile -t l <"$_ATTN_DIR/$1" 2>/dev/null || true
    rm -f "$_ATTN_DIR/$1"
  } 6>"$R/attention.lock"
  if [[ "${l[3]-}" =~ ^[0-9]+$ ]]; then makoctl dismiss -n "${l[3]}" >/dev/null 2>&1 || true; fi
}

# attention_toast CON_ID TITLE BODY [NOTIFY-SEND OPTIONS...]: the desktop notification of CON_ID's request. A
# request has one (a new one replaces it), and attention_seen dismisses it.
attention_toast() {
  local f="$_ATTN_DIR/$1" title=$2 body=$3 l=() opt=(-a ultron -p) id="" tmp
  shift 3
  [[ -s "$f" ]] || return 0
  mapfile -t l <"$f" || true
  if [[ "${l[3]-}" =~ ^[0-9]+$ ]]; then opt+=(-r "${l[3]}"); fi
  id=$(notify-send "${opt[@]}" "$@" "$title" "$body" 2>/dev/null) || true
  [[ "$id" =~ ^[0-9]+$ && "$id" != "${l[3]-}" ]] || return 0
  {
    flock 6
    if [[ -f "$f" ]]; then
      tmp=$(mktemp "$_ATTN_DIR/.new.XXXXXX")
      { head -n3 "$f"; printf '%s\n' "$id"; } >"$tmp"
      mv "$tmp" "$f"
    else
      # Answered while the notification went out.
      makoctl dismiss -n "$id" >/dev/null 2>&1 || true
    fi
  } 6>"$R/attention.lock"
}

# attention_raise TITLE [CON_ID [toast]]: the window CON_ID (default: the boss window) needs the user.
# Away -> phone; the window has focus -> nothing to do; focus mode -> urgent mark; else `jump`, which moves
# the user after the typing guard. With "toast" the request also gets its desktop notification (Jocasta's
# requests come with Jocasta's own).
attention_raise() {
  local title=${1:-An agent needs you} con=${2:-} toast=${3:-} ws="" old=() f tmp
  title=${title//[$'\t\n\r']/ }
  ensure_rundir
  if [[ -z "$con" ]]; then con=$(sway_ids '(.app_id // "") == "ultron-boss"' 2>/dev/null | tail -n1) || true; fi
  if [[ -n "$con" ]]; then ws=$(_con_ws "$con"); fi
  if [[ -z "$ws" ]]; then
    # No window to bring the user to: a notification (or the phone when away) is all there is.
    if is_away; then
      "$ULTRON_ROOT/bin/ultron" notify --phone --urgent "An agent needs you" "$title" || true
    elif [[ -n "$toast" ]]; then
      desktop_notify "An agent needs you" "$title"
    fi
    return 0
  fi

  mkdir -p "$_ATTN_DIR"
  f="$_ATTN_DIR/$con"
  {
    flock 6
    if [[ -s "$f" ]]; then mapfile -t old <"$f" || true; fi
    tmp=$(mktemp "$_ATTN_DIR/.new.XXXXXX")
    printf '%s\n%s\n%s\n' "${old[0]:-$(date -Iseconds)}" "$title" "$ws" >"$tmp"
    if [[ -n "${old[3]-}" ]]; then printf '%s\n' "${old[3]}" >>"$tmp"; fi
    mv "$tmp" "$f"
  } 6>"$R/attention.lock"

  if is_away; then
    "$ULTRON_ROOT/bin/ultron" notify --phone --urgent "An agent needs you" "$title" || true
  elif _con_focused "$con"; then
    attention_seen "$con"
  else
    if [[ -n "$toast" ]]; then attention_toast "$con" "An agent needs you" "$title"; fi
    if [[ -e "$R/focus" ]]; then
      swaymsg "[con_id=$con] urgent enable" >/dev/null 2>&1 || true
    else
      detach "$ULTRON_ROOT/bin/ultron" jump
    fi
  fi
}

attention_done() {
  local title=${1:-An agent finished}
  if is_away; then
    "$ULTRON_ROOT/bin/ultron" notify --phone "Finished" "$title" || true
  fi
}

# attention_go: what Super+A does. The oldest waiting window (entries of closed windows are dropped); else the
# newest shown window on a workspace still marked new ($R/shown-last, then the registry newest first); else the
# first marked workspace (`show code` marks 5 without a window of its own); else a "Nothing needs you" notice.
attention_go() {
  local con ws c="" n="" cands=()
  while con=$(_attn_oldest) && [[ -n "$con" ]]; do
    ws=$(_con_ws "$con")
    attention_seen "$con"
    if [[ -n "$ws" ]]; then
      goto_ws "$ws"
      swaymsg "[con_id=$con] focus" >/dev/null 2>&1 || true
      return 0
    fi
  done
  if [[ -s "$R/new" ]]; then
    if [[ -s "$R/shown-last" ]]; then read -r c <"$R/shown-last" || true; fi
    cands=("$c")
    if [[ -s "$R/shown" ]]; then mapfile -t -O 1 cands < <(tac "$R/shown" | cut -f1); fi
    for c in "${cands[@]}"; do
      [[ "$c" =~ ^[0-9]+$ ]] || continue
      ws=$(_con_ws "$c")
      if [[ -n "$ws" ]] && grep -qx -- "${ws%%:*}" "$R/new"; then
        goto_ws "$ws"
        swaymsg "[con_id=$c] focus" >/dev/null 2>&1 || true
        return 0
      fi
    done
    read -r n <"$R/new" || true
    if [[ "$n" =~ ^([1-9]|10)$ ]]; then
      goto_ws "${WS[$n]}"
      return 0
    fi
  fi
  desktop_notify "Nothing needs you" ""
}

cmd_attention() {
  ensure_rundir
  case ${1:-} in
  --raise) attention_raise "${2:-}" "$(_caller_window)" toast ;;
  --done)
    is_away || desktop_notify "Finished" "${2:-An agent finished}"
    attention_done "${2:-}"
    ;;
  --list)
    local time ws title _con
    while IFS=$'\t' read -r time ws title _con; do
      printf '%s\t%s\t%s\n' "$time" "$ws" "$title"
    done < <(attention_list)
    ;;
  --away)
    touch "$R/away"
    local _t _w title="" _c n
    n=$(attention_list | wc -l)
    if ((n)); then
      IFS=$'\t' read -r _t _w title _c < <(attention_list) || true
      if ((n > 1)); then title="$title (and $((n - 1)) more)"; fi
      # Detached: swayidle waits for this command, and a slow push would make it miss the resume.
      detach "$ULTRON_ROOT/bin/ultron" notify --phone --urgent "An agent needs you" "${title:-a question is waiting}"
    fi
    ;;
  "") attention_go ;;
  *) die "usage: ultron attention [--raise TITLE | --done TITLE | --list | --away]" ;;
  esac
}
