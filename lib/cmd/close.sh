# shellcheck shell=bash
# ultron close: close the focused window; asks first for the boss (closing it stops its agents).

cmd_close() {
  # The window is fixed before asking: a jump may move focus while the question is open.
  local id
  id=$(swaymsg -t get_tree | jq -r '[.. | objects | select(.focused == true)] | .[0].id // empty')
  [[ -n "$id" ]] || return 0
  if [[ $(focused_app_id) == ultron-boss ]]; then
    confirm "Close the boss? Its agents stop (they resume next time)" || return 0
  fi
  swaymsg "[con_id=$id] kill" >/dev/null
}
