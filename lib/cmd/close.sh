# shellcheck shell=bash
# ultron close: close the focused window; asks first for the boss (closing it stops every thread).

cmd_close() {
  if [[ $(focused_app_id) == ultron-boss ]] && { [[ $(boss_kind) != jocasta ]] || jocasta_running; }; then
    _confirm "Close the boss? It stops every thread (they resume next time)" || return 0
  fi
  swaymsg kill >/dev/null
}

# _confirm MESSAGE: fuzzel No/Yes; 0 only for Yes.
_confirm() {
  local ans
  ans=$(printf 'No\nYes\n' | fuzzel --dmenu --lines 2 --prompt "▸ " --mesg "$1") || return 1
  [[ $ans == Yes ]]
}
