# shellcheck shell=bash
# Shared helpers for bin/ultron, lib/cmd/*.sh and lib/install/*.sh.
# Sourced by bin/ultron after `set -euo pipefail`; ULTRON_ROOT is set by the caller.

ULTRON_USER=${USER:-$(id -un)}
ULTRON_CONF_DIR="$HOME/.config/ultron"
ULTRON_CONF="$ULTRON_CONF_DIR/ultron.conf"
ULTRON_GEN="$ULTRON_CONF_DIR/generated"
ULTRON_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ultron"
ULTRON_DATA="$HOME/.local/share/ultron"
NTFY_ENV="/etc/ultron/ntfy.env"
PREVIEW_PROFILE="$ULTRON_DATA/chromium-preview"
DOTFILES_DIR="$HOME/Projects/dotfiles"
JOCASTA_REPO_URL="https://github.com/zhivko-kocev/jocasta"
JOCASTA_NOTES="$ULTRON_DATA/jocasta-notes.md"
JOCASTA_DIR="$HOME/Projects/jocasta"
JOCASTA_INSTALL_DIR="$HOME/.local/lib/jocasta"
AGENT_BIN="$HOME/.local/lib/ultron/agent-bin"

# Runtime state ($R): idle2, away, focus, back, needs-you, jump.lock.
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR
R="$XDG_RUNTIME_DIR/ultron"

# Workspace number -> name (index 1..10).
WS=("" "1:boss" "2:review" "3:web" "4:watch" "5:code" "6:term" "7:chat" "8" "9" "10:sys")

# ---- output -----------------------------------------------------------------

if [[ -t 1 ]]; then
  _c_step=$'\e[1;33m' _c_ok=$'\e[1;32m' _c_warn=$'\e[1;35m' _c_err=$'\e[1;31m' _c_off=$'\e[0m'
else
  _c_step="" _c_ok="" _c_warn="" _c_err="" _c_off=""
fi

say() { printf '%s==>%s %s\n' "$_c_step" "$_c_off" "$*"; }
ok() { printf '%s ok%s %s\n' "$_c_ok" "$_c_off" "$*"; }
warn() { printf '%swarn%s %s\n' "$_c_warn" "$_c_off" "$*" >&2; }
die() {
  printf '%serror%s %s\n' "$_c_err" "$_c_off" "$*" >&2
  exit 1
}

# ---- environment --------------------------------------------------------------

is_vm() { systemd-detect-virt -q --vm; }
is_uefi() { [[ -d /sys/firmware/efi/efivars ]]; }
is_laptop() { compgen -G "/sys/class/power_supply/BAT*" >/dev/null; }
in_sway() { [[ -n "${SWAYSOCK:-}" ]] && swaymsg -t get_version >/dev/null 2>&1; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_rundir() { mkdir -p "$R"; }

# ultron_repo_url: where this checkout came from (a fork installs from itself).
ultron_repo_url() {
  git -C "$ULTRON_ROOT" config --get remote.origin.url 2>/dev/null || echo "https://github.com/zhivko-kocev/ultron"
}

# ---- settings -------------------------------------------------------------------
# KEY=value files: conf.d/*.conf in name order, then ultron.conf (the last one read wins).
# Files are parsed, never sourced. An empty value means "use the default".

_CONF_KEYS=(BOSS BROWSER THEME KEYBOARD KEYBOARD_VARIANT LOCAL_AI ASK_MODEL OLLAMA_GPU
  DOTFILES_REPO MOUNTS FIREWALL_ALLOW AWAY_AFTER LOCK_AFTER SCREEN_OFF_AFTER)
declare -A _CONF_DEFAULT=(
  [BOSS]=omp [BROWSER]=chromium [THEME]=gruvbox-dark [KEYBOARD]=us [KEYBOARD_VARIANT]=""
  [LOCAL_AI]=yes [ASK_MODEL]=qwen3:4b [OLLAMA_GPU]=auto [DOTFILES_REPO]="" [MOUNTS]="" [FIREWALL_ALLOW]=""
  [AWAY_AFTER]=300 [LOCK_AFTER]=600 [SCREEN_OFF_AFTER]=900
)
declare -A _CONF=()
_CONF_LOADED=0

# _kv_read FILE ARRAY: KEY=value lines of FILE into the associative array named ARRAY.
# Comment and blank lines are skipped; surrounding quotes and spaces are dropped.
_kv_read() {
  local -n _into=$2
  local line key val
  [[ -r "$1" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]} val=${BASH_REMATCH[2]}
    val=${val#"${val%%[![:space:]]*}"}
    val=${val%"${val##*[![:space:]]}"}
    if ((${#val} >= 2)) && [[ "$val" == \"*\" || "$val" == \'*\' ]]; then val=${val:1:${#val}-2}; fi
    # shellcheck disable=SC2004 # _into is an associative array: $key is a string key, not arithmetic
    _into[$key]=$val
  done <"$1"
}

conf_load() {
  local f
  _CONF=()
  for f in "$ULTRON_CONF_DIR"/conf.d/*.conf; do
    if [[ -e "$f" ]]; then _kv_read "$f" _CONF; fi
  done
  _kv_read "$ULTRON_CONF" _CONF
  _CONF_LOADED=1
}

conf_keys() { printf '%s\n' "${_CONF_KEYS[@]}"; }
conf_default() { printf '%s\n' "${_CONF_DEFAULT[$1]-}"; }

# conf_var VAR KEY [DEFAULT]: the setting into VAR (no subshell): else DEFAULT, else the built-in default.
conf_var() {
  local -n _out=$1
  ((_CONF_LOADED)) || conf_load
  _out=${_CONF[$2]-}
  if [[ -z "$_out" ]]; then
    if (($# >= 3)); then _out=$3; else _out=${_CONF_DEFAULT[$2]-}; fi
  fi
}

# conf_get KEY [DEFAULT]: print the setting.
conf_get() {
  local _v
  conf_var _v "$@"
  printf '%s\n' "$_v"
}

# conf_set KEY VALUE: create or replace KEY=VALUE in ultron.conf (the machine's own file).
conf_set() {
  local key=$1 val=$2 tmp
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "not a setting name: $key"
  [[ "$val" != *$'\n'* ]] || die "a setting can't span lines"
  mkdir -p "$ULTRON_CONF_DIR"
  [[ -e "$ULTRON_CONF" ]] || : >"$ULTRON_CONF"
  tmp=$(mktemp "$ULTRON_CONF_DIR/.ultron.conf.XXXXXX")
  grep -v -E "^[[:space:]]*${key}[[:space:]]*=" "$ULTRON_CONF" >"$tmp" || true
  printf '%s=%s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" "$ULTRON_CONF"
  _CONF_LOADED=0
}

boss_kind() { conf_get BOSS; }
browser_cmd() { conf_get BROWSER; }
ask_model() { conf_get ASK_MODEL; }

# conf_mounts: the MOUNTS setting as "SPEC MOUNTPOINT" lines (SPEC = LABEL=x, UUID=x or /dev/x).
conf_mounts() {
  local item mounts
  conf_var mounts MOUNTS
  for item in $mounts; do
    if [[ "$item" == ?*:/?* ]]; then
      printf '%s /%s\n' "${item%%:/*}" "${item#*:/}"
    else
      warn "MOUNTS entry '$item' isn't SPEC:/mountpoint: skipped"
    fi
  done
}

# ---- theme ------------------------------------------------------------------------
# A theme is a KEY=value palette file (hex colours without #). Yours in ~/.config/ultron/themes win.

declare -A _THEME=()
_THEME_LOADED=""

# theme_path [NAME]: the file of a theme; 1 when there is none.
theme_path() {
  local name=${1:-} d
  [[ -n "$name" ]] || conf_var name THEME
  for d in "$ULTRON_CONF_DIR/themes" "$ULTRON_ROOT/themes"; do
    if [[ -f "$d/$name.conf" ]]; then
      printf '%s\n' "$d/$name.conf"
      return 0
    fi
  done
  return 1
}

theme_names() {
  local f
  for f in "$ULTRON_ROOT"/themes/*.conf "$ULTRON_CONF_DIR"/themes/*.conf; do
    if [[ -e "$f" ]]; then basename "$f" .conf; fi
  done | sort -u
}

# theme_load [NAME]: fills _THEME. gruvbox-dark is read first, so a partial theme still has every key.
theme_load() {
  local name=${1:-} file key
  [[ -n "$name" ]] || conf_var name THEME
  _THEME=()
  _kv_read "$ULTRON_ROOT/themes/gruvbox-dark.conf" _THEME
  if file=$(theme_path "$name"); then
    _kv_read "$file" _THEME
  else
    warn "no theme named '$name': using gruvbox-dark"
  fi
  for key in "${!_THEME[@]}"; do _THEME[$key]=${_THEME[$key]#\#}; done
  _THEME_LOADED=$name
}

# theme_get KEY: a palette value of the current theme (hex without #). In a loop, call theme_load
# once and read ${_THEME[KEY]} instead.
theme_get() {
  [[ -n "$_THEME_LOADED" ]] || theme_load
  printf '%s\n' "${_THEME[$1]-}"
}

# ---- boss, phone, presence ----------------------------------------------------------

jocasta_data_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/jocasta/data"; }
jocasta_running() { pgrep -x jocasta >/dev/null 2>&1; }

# ntfy_load: sets NTFY_URL/NTFY_TOKEN from /etc/ultron/ntfy.env; 1 when phone alerts aren't set up.
ntfy_load() {
  [[ -r "$NTFY_ENV" ]] || return 1
  local -A env=()
  _kv_read "$NTFY_ENV" env
  NTFY_URL=${env[NTFY_URL]-} NTFY_TOKEN=${env[NTFY_TOKEN]-}
  [[ -n "$NTFY_URL" && -n "$NTFY_TOKEN" ]]
}

is_away() { [[ -e "$R/away" ]] || pgrep -x swaylock >/dev/null 2>&1; }

# wait_idle SECONDS: wait for the typing guard ($R/idle2); 1 on timeout.
wait_idle() {
  local limit=$1 waited=0
  ensure_rundir
  until [[ -e "$R/idle2" ]]; do
    ((waited >= limit * 10)) && return 1
    sleep 0.1
    waited=$((waited + 1))
  done
}

# ---- sway -----------------------------------------------------------------------------

# sway_ids JQ_FILTER: con_ids of windows matching the jq select filter, oldest first.
sway_ids() {
  swaymsg -t get_tree | jq -r "[.. | objects | select(has(\"app_id\") or has(\"window_properties\")) | select($1) | .id] | sort | .[]"
}

# wait_window APP_ID_REGEX [TIMEOUT_S]: newest con_id whose app_id matches; 1 on timeout.
wait_window() {
  local re=$1 limit=${2:-10} i id
  for ((i = 0; i < limit * 10; i++)); do
    id=$(sway_ids "(.app_id // \"\") | test(\"$re\")" | tail -n1)
    if [[ -n "$id" ]]; then
      printf '%s\n' "$id"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# wait_new_window BEFORE_IDS JQ_FILTER [TIMEOUT_S]: con_id of a window matching the filter that is
# not in BEFORE_IDS (space-separated); 1 on timeout. For apps whose app_id can't be chosen.
wait_new_window() {
  local before=" $1 " filter=$2 limit=${3:-20} i cand
  for ((i = 0; i < limit * 10; i++)); do
    while IFS= read -r cand; do
      if [[ -n "$cand" && "$before" != *" $cand "* ]]; then
        printf '%s\n' "$cand"
        return 0
      fi
    done < <(sway_ids "$filter")
    sleep 0.1
  done
  return 1
}

focused_ws() { swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name'; }
focused_app_id() { swaymsg -t get_tree | jq -r '[.. | objects | select(.focused == true)] | .[0].app_id // ""'; }
focused_title() { swaymsg -t get_tree | jq -r '[.. | objects | select(.focused == true)] | .[0].name // ""'; }

# ws_name N: workspace name for number N.
ws_name() {
  local n=$1
  [[ "$n" =~ ^([1-9]|10)$ ]] || die "workspace must be 1-10, got '$n'"
  printf '%s\n' "${WS[$n]}"
}

# detach CMD...: run fully detached from this process (new session, no stdio).
detach() { setsid -f "$@" </dev/null >/dev/null 2>&1; }

# ---- desktop UI ---------------------------------------------------------------------------

desktop_notify() { notify-send -a ultron "$@" 2>/dev/null || true; }

# pick PROMPT [FUZZEL_OPTION...]: options on stdin, the chosen line on stdout; 1 when cancelled.
pick() {
  local prompt=$1
  shift
  fuzzel --dmenu --prompt "$prompt ▸ " "$@"
}

# ask_text PROMPT [FUZZEL_OPTION...]: one line of text from the user; 1 when cancelled or empty.
ask_text() {
  local prompt=$1 out
  shift
  out=$(fuzzel --dmenu --lines 0 --prompt "$prompt ▸ " "$@" </dev/null) || return 1
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
}

# confirm MESSAGE: No/Yes; 0 only for Yes.
confirm() {
  local ans
  ans=$(printf 'No\nYes\n' | fuzzel --dmenu --lines 2 --prompt "▸ " --mesg "$1") || return 1
  [[ $ans == Yes ]]
}

# term_run [--hold] [--title T] -- CMD...: run CMD in a floating terminal (app_id ultron-float).
term_run() {
  local args=(--app-id=ultron-float)
  while (($#)); do
    case $1 in
    --hold) args+=(--hold) ;;
    --title)
      args+=(--title="${2:?--title needs a value}")
      shift
      ;;
    --)
      shift
      break
      ;;
    *) break ;;
    esac
    shift
  done
  (($#)) || die "term_run needs a command"
  detach foot "${args[@]}" -- "$@"
}

# ---- install helpers --------------------------------------------------------------------------

_ULTRON_SUDO_PID=""

# sudo_keepalive: ask once, refresh in the background until sudo_drop or this shell's exit.
sudo_keepalive() {
  [[ -z "$_ULTRON_SUDO_PID" ]] || return 0
  sudo -v || die "sudo failed"
  # No inherited stdout/stderr: a leftover `sleep` would otherwise keep `ultron install | tee log` open.
  (while kill -0 "$$" 2>/dev/null; do
    sudo -n -v 2>/dev/null || true
    sleep 30
  done) </dev/null >/dev/null 2>&1 &
  _ULTRON_SUDO_PID=$!
  trap sudo_drop EXIT
}

# sudo_drop: stop refreshing and throw the cached sudo ticket away, so nothing that runs later in
# this terminal (third-party installers, a pasted command) is root without a new password.
sudo_drop() {
  if [[ -n "$_ULTRON_SUDO_PID" ]]; then
    kill "$_ULTRON_SUDO_PID" 2>/dev/null || true
    _ULTRON_SUDO_PID=""
  fi
  sudo -k 2>/dev/null || true
}

# list_packages FILE...: package names from list files (comments and blanks stripped).
list_packages() { sed -e 's/#.*//' -e 's/[[:space:]]\+/\n/g' "$@" | sed '/^$/d'; }
