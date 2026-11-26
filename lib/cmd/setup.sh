# shellcheck shell=bash
# ultron setup TOPIC: small guided steps (the menu's Setup section). Cancelling a question
# exits with 130 so the menu can go back instead of closing.

_SETUP_TOPICS="wifi bluetooth audio display keyboard browser boss git dotfiles timezone remote phone model"

_setup_cancel() { exit 130; }

_setup_usage() {
  cat <<'EOF'
usage: ultron setup TOPIC

  wifi        Wi-Fi and network connections
  bluetooth   pair Bluetooth devices
  audio       volume, outputs and inputs
  display     screens: resolution, scale, position
  keyboard    keyboard layout(s)
  browser     your everyday browser
  boss        the agent on workspace 1
  git         your name and email for git commits
  dotfiles    your personal dotfiles repo
  timezone    the clock's time zone
  remote      remote access with Tailscale
  phone       phone alerts (needs remote)
  model NAME  download a local AI model for 'ask'
EOF
}

_setup_display() {
  local dir="$ULTRON_CONF_DIR/sway" file outputs="" first="HDMI-A-1"
  file="$dir/10-outputs.conf"
  if [[ ! -e "$file" ]]; then
    mkdir -p "$dir"
    if in_sway; then
      outputs=$(swaymsg -t get_outputs -r | jq -r '.[] |
        "#   \(.name): \(.make // "") \(.model // "")",
        "#     now: " + (if .active and .current_mode then
          "\(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh / 1000)Hz, scale \(.scale // 1), position \(.rect.x) \(.rect.y)"
          else "off" end),
        "#     modes: " + ([.modes[]? | "\(.width)x\(.height)@\(.refresh / 1000)Hz"] | unique | join(" "))' || true)
      first=$(swaymsg -t get_outputs -r | jq -r '.[0].name // "HDMI-A-1"' || echo HDMI-A-1)
    fi
    {
      echo "# Screens. Each line without # is a sway output command (man sway-output)."
      echo "# Save, then press Super+Shift+C to apply."
      echo "#"
      echo "# Connected now:"
      if [[ -n "$outputs" ]]; then echo "$outputs"; else echo "#   (start the desktop and run 'ultron setup display' to list them)"; fi
      echo "#"
      echo "# Examples (remove the # to use one):"
      echo "# output $first mode 2560x1440@144Hz scale 1.25 position 0 0"
      echo "# output DP-1 mode 1920x1080@60Hz position 2048 0"
    } >"$file"
  fi
  have nano || die "nano is missing: run 'ultron install packages'"
  term_run --title Display -- nano "$file"
  say "Editing $file; changes apply when you press Super+Shift+C"
  desktop_notify "Display settings" "Save the file, then press Super+Shift+C to apply"
}

_setup_keyboard() {
  local layout
  layout=$(ask_text "Keyboard layout" --mesg "Examples: us, de, gb, fr; several, comma-separated: us,mk. Now: $(conf_get KEYBOARD)") || _setup_cancel
  layout=${layout// /}
  [[ "$layout" =~ ^[a-z][a-z0-9_-]*(,[a-z][a-z0-9_-]*)*$ ]] || die "'$layout' isn't a layout list: use names like us or us,mk"
  "$ULTRON_ROOT/bin/ultron" conf set KEYBOARD "$layout"
  desktop_notify "Keyboard" "Layout set to $layout"
}

_setup_browser() {
  local b choice found=()
  for b in chromium google-chrome-stable firefox brave vivaldi-stable; do
    if have "$b"; then found+=("$b"); fi
  done
  ((${#found[@]})) || die "no browser is installed: install one with 'ultron pkg install chromium'"
  choice=$(printf '%s\n' "${found[@]}" | pick "Browser (now: $(browser_cmd))" --lines "${#found[@]}") || _setup_cancel
  "$ULTRON_ROOT/bin/ultron" conf set BROWSER "$choice"
  desktop_notify "Browser" "$choice opens your links from now on"
}

_setup_boss() {
  local a choice found=()
  for a in omp jocasta claude codex gemini opencode; do
    if have "$a"; then found+=("$a"); fi
  done
  ((${#found[@]})) || die "no agent is installed: add one with the menu (Install, then Agent) or 'ultron agent add NAME'"
  choice=$(printf '%s\n' "${found[@]}" | pick "Boss agent (now: $(boss_kind))" --lines "${#found[@]}") || _setup_cancel
  conf_set BOSS "$choice"
  ok "The boss is now $choice. Close the boss window (Super+W on workspace 1), then press Super+B"
  desktop_notify "Boss: $choice" "Close the boss window (Super+W on workspace 1), then press Super+B"
}

_setup_git() {
  local name email
  have git || die "git is missing: run 'ultron install packages'"
  name=$(ask_text "Your name" --mesg "Shown on your git commits. Now: $(git config --global user.name || echo 'not set')") || _setup_cancel
  email=$(ask_text "Your email" --mesg "Shown on your git commits. Now: $(git config --global user.email || echo 'not set')") || _setup_cancel
  [[ "$email" == *@* ]] || die "'$email' doesn't look like an email address"
  git config --global user.name "$name"
  git config --global user.email "$email"
  ok "git commits are signed as $name <$email>"
  desktop_notify "Git identity" "$name <$email>"
}

_setup_dotfiles() {
  local url
  url=$(ask_text "Dotfiles repo" --mesg "A git URL, or owner/repo on GitHub. It needs an install.sh. Now: $(conf_get DOTFILES_REPO "not set")") || _setup_cancel
  if [[ "$url" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then url="https://github.com/$url"; fi
  [[ "$url" =~ ^(https?://|git@|ssh://) ]] || die "'$url' isn't a git URL (https://…, git@… or owner/repo)"
  conf_set DOTFILES_REPO "$url"
  term_run --hold --title Dotfiles -- "$ULTRON_ROOT/bin/ultron" install dotfiles
}

_setup_timezone() {
  local tz
  have timedatectl || die "timedatectl is missing"
  tz=$(timedatectl list-timezones | pick "Time zone (now: $(timedatectl show -p Timezone --value 2>/dev/null || echo '?'))") || _setup_cancel
  term_run --title "Time zone" -- sudo timedatectl set-timezone "$tz"
}

_setup_model() {
  local name=${1:-}
  have ollama || die "local AI isn't installed: run 'ultron conf set LOCAL_AI yes', then 'ultron install packages ai'"
  if [[ -z "$name" ]]; then
    [[ -t 0 ]] || die "usage: ultron setup model NAME   (names: https://ollama.com/library, e.g. qwen3:4b)"
    read -rp "Model to download (e.g. qwen3:4b, from https://ollama.com/library): " name || _setup_cancel
    [[ -n "$name" ]] || _setup_cancel
  fi
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || die "'$name' isn't a model name (e.g. qwen3:4b)"
  say "Downloading $name (this can take a while)…"
  ollama pull "$name" || die "ollama could not download '$name': check the name at https://ollama.com/library and that ollama is running (ultron doctor)"
  "$ULTRON_ROOT/bin/ultron" conf set ASK_MODEL "$name"
  ok "'ask' now uses $name. omp's commit role follows on the next 'ultron update'"
}

cmd_setup() {
  local topic=${1:-}
  case $topic in
  "" | -h | --help | help) _setup_usage ;;
  wifi)
    have nmtui || die "nmtui (NetworkManager) is missing: run 'ultron install packages'"
    term_run --title Network -- nmtui
    ;;
  bluetooth)
    compgen -G "/sys/class/bluetooth/hci*" >/dev/null || die "this computer has no Bluetooth adapter (or it is switched off in the firmware)"
    have bluetui || die "bluetui isn't installed: run 'ultron install hardware'"
    term_run --title Bluetooth -- bluetui
    ;;
  audio)
    have pavucontrol || die "pavucontrol is missing: run 'ultron install packages'"
    detach pavucontrol
    ;;
  display) _setup_display ;;
  keyboard) _setup_keyboard ;;
  browser) _setup_browser ;;
  boss) _setup_boss ;;
  git) _setup_git ;;
  dotfiles) _setup_dotfiles ;;
  timezone) _setup_timezone ;;
  remote) term_run --hold --title "Remote access" -- "$ULTRON_ROOT/bin/ultron" install net ;;
  phone) term_run --hold --title "Phone alerts" -- "$ULTRON_ROOT/bin/ultron" install ntfy ;;
  model) _setup_model "${2:-}" ;;
  *)
    _setup_usage >&2
    die "unknown setup topic '$topic' (topics: $_SETUP_TOPICS)"
    ;;
  esac
}
