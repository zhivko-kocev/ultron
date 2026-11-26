# shellcheck shell=bash
# ultron lock: lock the screen and count as away until unlocked.
# swaylock runs detached: swayidle -w waits for its commands, and a blocking lock would hold back its later timeouts.

cmd_lock() {
  ensure_rundir
  pgrep -x swaylock >/dev/null 2>&1 && return 0
  touch "$R/away"
  # shellcheck disable=SC2016 # $1 expands in the child bash
  detach bash -c 'swaylock; rm -f "$1"' _ "$R/away"
}
