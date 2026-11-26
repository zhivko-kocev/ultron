# shellcheck shell=bash
# ultron jump: started by `attention --raise`. Once the user stops typing, take them to the oldest window that
# needs them (what Super+A does). One jump at a time: a queued one waits until the user has typed in the
# window the previous one brought them to, so a queue of requests never moves them twice in a row unread.

# shellcheck source=attention.sh
source "$ULTRON_ROOT/lib/cmd/attention.sh"

# _jump_mark: the oldest waiting window gets the urgent mark (workspace turns red in the bar).
_jump_mark() {
  local con
  con=$(_attn_oldest)
  if [[ -n "$con" ]]; then swaymsg "[con_id=$con] urgent enable" >/dev/null 2>&1 || true; fi
}

cmd_jump() {
  (($# == 0)) || die "usage: ultron jump (it takes no arguments; agents call: ultron attention --raise TITLE)"
  ensure_rundir
  exec 9>"$R/jump.lock"
  if ! flock -w 120 9 || ! wait_idle 60; then
    _jump_mark
    desktop_notify -u critical "An agent needs you" "Press Super+A"
    return 0
  fi
  # Nothing waits any more (the user got there first), or they can't be moved now.
  [[ -n "$(_attn_oldest)" ]] || return 0
  if is_away; then return 0; fi
  if [[ -e "$R/focus" ]]; then
    _jump_mark
    return 0
  fi
  attention_go
  # Hold the lock until the user types (at most 60 s): the next request waits for that, then for the guard.
  local i
  for ((i = 0; i < 600; i++)); do
    [[ -e "$R/idle2" ]] || break
    nap 0.1
  done
}
