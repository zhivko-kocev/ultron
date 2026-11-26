# shellcheck shell=bash
# ultron menu [SECTION]: one menu for everything (Super+Alt+Space). Esc goes back one level.
# SECTION (install, remove, setup, style, screenshot, system) opens that part directly;
# Esc there closes the menu.

# Navigation is passed in flags, not exit codes, so errexit stays on inside every step:
#   _MENU_UP    Esc on a section's list: back to the top level
#   _MENU_BACK  Esc on a question inside a step: show its section again
#   _MENU_DONE  a step ran (or Esc at the top level): close
_MENU_UP=0
_MENU_BACK=0
_MENU_DONE=0
_MENU_RC=0

_menu_back() { _MENU_BACK=1; }

_menu_fail() { desktop_notify -u critical "$1" "$2"; }

# _menu_do ARGS…: run `ultron ARGS…`. The menu has no terminal, so a failure becomes a
# notification; exit 130 (a cancelled question) goes back. The exit code is left in _MENU_RC.
_menu_do() {
  local out
  _MENU_RC=0
  out=$("$ULTRON_ROOT/bin/ultron" "$@" 2>&1) || _MENU_RC=$?
  if ((_MENU_RC == 130)); then
    _menu_back
  elif ((_MENU_RC != 0)); then
    _menu_fail "ultron $1: something went wrong" "$(tail -n 4 <<<"$out")"
  fi
}

# _menu_list VAR ARGS…: output of `ultron ARGS…` into VAR; 1 (after a notification) on failure.
_menu_list() {
  local -n _ml_out=$1
  shift
  if ! _ml_out=$("$ULTRON_ROOT/bin/ultron" "$@" 2>&1); then
    _menu_fail "ultron $1: something went wrong" "$(tail -n 4 <<<"$_ml_out")"
    return 1
  fi
}

# _menu_term TITLE [--hold] ARGS…: `ultron ARGS…` in a floating terminal.
_menu_term() {
  local hold=() title=$1
  shift
  if [[ $1 == --hold ]]; then
    hold=(--hold)
    shift
  fi
  term_run "${hold[@]}" --title "$title" -- "$ULTRON_ROOT/bin/ultron" "$@"
}

# ---- Install ----------------------------------------------------------------------------------

_menu_install_dev() {
  local list c
  _menu_list list dev list || return 0
  c=$(pick "Dev tool (✓ = installed)" <<<"$list") || {
    _menu_back
    return 0
  }
  _menu_term "Install ${c%% *}" --hold dev add "${c%% *}"
}

_menu_install_agent() {
  local list c
  _menu_list list agent list || return 0
  c=$(awk 'NF { print $1 }' <<<"$list" | pick Agent) || {
    _menu_back
    return 0
  }
  _menu_term "Install $c" --hold agent add "$c"
}

_menu_install_webapp() {
  local name url ws
  name=$(ask_text "Web app name" --mesg "As it shows in the app list, e.g. WhatsApp") || {
    _menu_back
    return 0
  }
  url=$(ask_text "Address" --mesg "The page it opens, e.g. https://web.whatsapp.com/") || {
    _menu_back
    return 0
  }
  ws=$(printf '%s\n' none 7 8 9 | pick "Workspace for its windows" --lines 4) || {
    _menu_back
    return 0
  }
  if [[ $ws == none ]]; then
    _menu_do webapp add "$name" "$url"
  else
    _menu_do webapp add "$name" "$url" --ws "$ws"
  fi
  if ((_MENU_RC == 0)); then
    desktop_notify "Web app" "$name is ready: find it with Super+Space"
  fi
}

_menu_install_model() {
  local m
  m=$(ask_text "AI model" --mesg "An ollama model name, e.g. qwen3:4b (see ollama.com/library)") || {
    _menu_back
    return 0
  }
  _menu_term "AI model" --hold setup model "$m"
}

_menu_install() {
  local c
  c=$(printf '%s\n' "Package…" "Dev tool…" "Agent…" "Web app…" "AI model…" | pick Install --lines 5) || {
    _MENU_UP=1
    return 0
  }
  case $c in
  "Package…") term_run --title "Install packages" -- "$ULTRON_ROOT/bin/ultron" pkg install ;;
  "Dev tool…") _menu_install_dev ;;
  "Agent…") _menu_install_agent ;;
  "Web app…") _menu_install_webapp ;;
  "AI model…") _menu_install_model ;;
  esac
}

# ---- Remove -----------------------------------------------------------------------------------

_menu_remove_webapp() {
  local list c
  _menu_list list webapp list || return 0
  if [[ -z "$list" ]]; then
    desktop_notify "Web apps" "You have no web apps yet (Install, then Web app)"
    return 0
  fi
  c=$(awk -F '\t' '{ print $1 " · " $2 }' <<<"$list" | pick "Remove web app") || {
    _menu_back
    return 0
  }
  _menu_do webapp remove "${c%% · *}"
  if ((_MENU_RC == 0)); then
    desktop_notify "Web app removed" "${c#* · }"
  fi
}

_menu_remove_dev() {
  local list c
  _menu_list list dev list || return 0
  list=$(grep -F '✓' <<<"$list" || true)
  if [[ -z "$list" ]]; then
    desktop_notify "Dev tools" "No dev tools are installed"
    return 0
  fi
  c=$(pick "Remove dev tool" <<<"$list") || {
    _menu_back
    return 0
  }
  _menu_term "Remove ${c%% *}" --hold dev remove "${c%% *}"
}

_menu_remove() {
  local c
  c=$(printf '%s\n' "Package…" "Web app…" "Dev tool…" | pick Remove --lines 3) || {
    _MENU_UP=1
    return 0
  }
  case $c in
  "Package…") term_run --title "Remove packages" -- "$ULTRON_ROOT/bin/ultron" pkg remove ;;
  "Web app…") _menu_remove_webapp ;;
  "Dev tool…") _menu_remove_dev ;;
  esac
}

# ---- Setup, Style, Screenshot, System -----------------------------------------------------------

_menu_setup() {
  local c topic items=("Wi-Fi/Network")
  if compgen -G "/sys/class/bluetooth/hci*" >/dev/null; then items+=(Bluetooth); fi
  items+=(Audio Display Keyboard Browser "Boss agent" "Git identity" Dotfiles "Time zone"
    "Remote access (Tailscale)" "Phone alerts")
  c=$(printf '%s\n' "${items[@]}" | pick Setup --lines "${#items[@]}") || {
    _MENU_UP=1
    return 0
  }
  case $c in
  "Wi-Fi/Network") topic=wifi ;;
  Bluetooth) topic=bluetooth ;;
  Audio) topic=audio ;;
  Display) topic=display ;;
  Keyboard) topic=keyboard ;;
  Browser) topic=browser ;;
  "Boss agent") topic=boss ;;
  "Git identity") topic=git ;;
  Dotfiles) topic=dotfiles ;;
  "Time zone") topic=timezone ;;
  "Remote access (Tailscale)") topic=remote ;;
  "Phone alerts") topic=phone ;;
  *) return 0 ;;
  esac
  _menu_do setup "$topic"
}

_menu_style() {
  local c
  c=$(printf '%s\n' "Theme…" | pick Style --lines 1) || {
    _MENU_UP=1
    return 0
  }
  case $c in
  "Theme…") _menu_do theme ;;
  esac
}

_menu_screenshot() {
  local c
  c=$(printf '%s\n' Region "Full screen" "For the boss" | pick Screenshot --lines 3) || {
    _MENU_UP=1
    return 0
  }
  case $c in
  Region) _menu_do shot region ;;
  "Full screen") _menu_do shot full ;;
  "For the boss") _menu_do snap ;;
  esac
}

_menu_system() { _menu_do power; }

# _menu_section NAME: show a section until a step runs (_MENU_DONE=1) or Esc on its list.
_menu_section() {
  while :; do
    _MENU_UP=0
    _MENU_BACK=0
    "_menu_$1"
    if ((_MENU_UP)); then return 0; fi
    if ((!_MENU_BACK)); then
      _MENU_DONE=1
      return 0
    fi
  done
}

# ---- top level ----------------------------------------------------------------------------------

_menu_update() {
  if in_sway; then swaymsg workspace "$(ws_name 10)" >/dev/null; fi
  detach foot --app-id=ultron-sys-update --hold -- "$ULTRON_ROOT/bin/ultron" update
}

_menu_top() {
  local c
  c=$(printf '%s\n' Apps Keys Boss "New thread" "Install ▸" "Remove ▸" "Setup ▸" "Style ▸" \
    Update Doctor "Focus mode" "Screenshot ▸" "System ▸" | pick ultron --lines 13) || {
    _MENU_DONE=1
    return 0
  }
  case $c in
  "Install ▸") _menu_section install ;;
  "Remove ▸") _menu_section remove ;;
  "Setup ▸") _menu_section setup ;;
  "Style ▸") _menu_section style ;;
  "Screenshot ▸") _menu_section screenshot ;;
  "System ▸") _menu_section system ;;
  *)
    _MENU_DONE=1
    case $c in
    Apps) detach fuzzel ;;
    Keys) _menu_do keys ;;
    Boss) _menu_do boss ;;
    "New thread") _menu_do task ;;
    Update) _menu_update ;;
    Doctor) _menu_term Doctor --hold doctor ;;
    "Focus mode") _menu_do focus toggle ;;
    esac
    ;;
  esac
}

cmd_menu() {
  local section=${1:-}
  if [[ -n "$section" ]]; then
    case $section in
    install | remove | setup | style | screenshot | system) _menu_section "$section" ;;
    *) die "unknown menu section '$section' (sections: install remove setup style screenshot system)" ;;
    esac
    return 0
  fi
  while :; do
    _MENU_DONE=0
    _menu_top
    if ((_MENU_DONE)); then return 0; fi
  done
}
