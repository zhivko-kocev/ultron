# shellcheck shell=bash
# ultron idle: (re)start swayidle with the generated config. Run by sway at start and on reload.
# Stay awake (ultron toggle awake, flag $R/awake): only the 2-second typing guard runs; no away, lock or
# screen-off timeouts.

cmd_idle() {
  local conf="$ULTRON_GEN/swayidle"
  ensure_rundir
  pkill -x swayidle 2>/dev/null || true
  # A killed swayidle never ran its resume commands: clear what it may have left behind.
  rm -f "$R/idle2" "$R/away"
  if [[ -e "$R/awake" ]]; then
    exec swayidle -w timeout 2 "touch '$R/idle2'" resume "rm -f '$R/idle2'" \
      before-sleep 'swaylock -f' lock 'ultron lock'
  fi
  [[ -r "$conf" ]] || die "$conf is missing: run ultron apply"
  exec swayidle -w -C "$conf"
}
