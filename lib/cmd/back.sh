# shellcheck shell=bash
# ultron back: return to the workspace before the last jump.

cmd_back() {
  if [[ -s "$R/back" ]]; then
    swaymsg "workspace \"$(<"$R/back")\"" >/dev/null
  else
    swaymsg 'workspace back_and_forth' >/dev/null
  fi
}
