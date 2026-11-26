# shellcheck shell=bash
# ultron task: open Jocasta's own "New thread" question (Ctrl+B, then Alt+N) in the boss window.

cmd_task() {
  source "$ULTRON_ROOT/lib/cmd/boss.sh"
  cmd_boss
  [[ $(boss_kind) == jocasta ]] || return 0
  sleep 0.15
  wtype -M ctrl b -m ctrl
  wtype -M alt n -m alt
}
