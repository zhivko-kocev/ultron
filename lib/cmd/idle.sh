# shellcheck shell=bash
# ultron idle: (re)start swayidle with the generated config. Run by sway at start and on reload.

cmd_idle() {
  local conf="$ULTRON_GEN/swayidle"
  [[ -r "$conf" ]] || die "$conf is missing: run ultron apply"
  ensure_rundir
  pkill -x swayidle 2>/dev/null || true
  # A killed swayidle never ran its resume commands: clear what it may have left behind.
  rm -f "$R/idle2" "$R/away"
  exec swayidle -w -C "$conf"
}
