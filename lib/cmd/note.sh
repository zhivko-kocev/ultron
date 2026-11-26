# shellcheck shell=bash
# ultron note jocasta: note a Jocasta friction point for the improvement loop.

cmd_note() {
  [[ ${1:-} == jocasta ]] || die "usage: ultron note jocasta"
  local title text
  title=$(focused_title 2>/dev/null || true)
  text=$(fuzzel --dmenu --lines 0 --prompt "Jocasta note ▸ " </dev/null) || return 0
  [[ -n "$text" ]] || return 0
  mkdir -p "${JOCASTA_NOTES%/*}"
  printf -- '- %s [%s] %s\n' "$(date -Iseconds)" "$title" "$text" >>"$JOCASTA_NOTES"
  desktop_notify "Noted" "$text"
}
