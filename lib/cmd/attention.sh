# shellcheck shell=bash
# ultron attention [--away]: go to whatever needs you; --away (swayidle) marks you away and sends one digest push.

cmd_attention() {
  ensure_rundir
  if [[ ${1:-} == --away ]]; then
    touch "$R/away"
    if [[ -s "$R/needs-you" ]]; then
      local title
      title=$(sed -n 2p "$R/needs-you")
      "$ULTRON_ROOT/bin/ultron" notify --phone --urgent "Jocasta needs you" "Jocasta needs you: ${title:-a question is waiting}"
    fi
    return 0
  fi
  [[ $# -eq 0 ]] || die "usage: ultron attention [--away]"

  if [[ -e "$R/needs-you" ]]; then
    source "$ULTRON_ROOT/lib/cmd/boss.sh"
    cmd_boss
  elif ! swaymsg '[urgent=latest] focus' >/dev/null 2>&1; then
    desktop_notify "Nothing needs you" ""
  fi
}
