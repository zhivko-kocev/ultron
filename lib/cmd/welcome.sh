# shellcheck shell=bash
# ultron welcome [--once]: the first-login guide. --once shows it only the first time.

_welcome_text() {
  local boss intro
  boss=$(boss_kind)
  if [[ "${boss%% *}" == jocasta ]]; then
    intro="Workspace 1 holds your boss, Jocasta: you talk to its boss pane, and it runs
agent threads for your projects (~/Projects). Super+B takes you there. The
first step: type /login in the boss pane to sign in."
  else
    intro="Workspace 1 holds your boss agent ($boss); Super+B takes you there. The first
time, sign it in: omp asks by itself, in claude type /login, other agents
print their own steps."
  fi
  cat <<EOF
Welcome to ultron.

  Super+Alt+Space   the menu: install, remove, setup, style, update, power
  Super+K           every key, searchable
  Super+Space       open an app            Super+Return   a terminal
  Super+1 … 0       go to a workspace      Super+W        close a window

$intro

Wi-Fi, Bluetooth, sound, screens, keyboard layout, browser, git identity
and time zone: menu, then Setup.

More agents (claude, codex, gemini, …), languages (node, python, go, …),
apps and web apps: menu, then Install.

Keep everything current:   ultron update
Check that all is well:    ultron doctor

Your settings live in ~/.config/ultron/ (ultron conf edit opens them).
How to change anything:    $ULTRON_ROOT/docs/customize.md

Show this again any time:  ultron welcome
Close this window:         Super+W
EOF
}

cmd_welcome() {
  case ${1:-} in
  --once)
    [[ -e "$ULTRON_STATE/welcomed" ]] && return 0
    mkdir -p "$ULTRON_STATE"
    : >"$ULTRON_STATE/welcomed"
    term_run --hold --title Welcome -- "$ULTRON_ROOT/bin/ultron" welcome
    ;;
  "") _welcome_text ;;
  *) die "usage: ultron welcome [--once]" ;;
  esac
}
