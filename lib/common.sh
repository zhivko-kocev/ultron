# shellcheck shell=bash
# Shared helpers for bin/ultron, lib/cmd/*.sh and lib/install/*.sh.
# Sourced by bin/ultron after `set -euo pipefail`; ULTRON_ROOT is set by the caller.

ULTRON_USER="zhivko-kocev"
ULTRON_REPO_URL="https://github.com/zhivko-kocev/ultron"
DOTFILES_REPO_URL="https://github.com/zhivko-kocev/dotfiles"
JOCASTA_REPO_URL="https://github.com/zhivko-kocev/jocasta"
SSD_UUID="f4d0a7a7-ee8c-458c-91aa-3f2dceacb527"
SSD_MOUNT="/mnt/projects"
ULTRON_CONF="$HOME/.config/ultron/ultron.conf"
NTFY_ENV="/etc/ultron/ntfy.env"
PREVIEW_PROFILE="$HOME/.local/share/ultron/chromium-preview"
JOCASTA_NOTES="$HOME/.local/share/ultron/jocasta-notes.md"
JOCASTA_DIR="$HOME/Projects/jocasta"
JOCASTA_INSTALL_DIR="$HOME/.local/lib/jocasta"
AGENT_BIN="$HOME/.local/lib/ultron/agent-bin"
OMP_COMMIT_ROLE="ollama/qwen3:4b, anthropic/claude-haiku-5-5:low"

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
in_sway() { [[ -n "${SWAYSOCK:-}" ]] && swaymsg -t get_version >/dev/null 2>&1; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_rundir() { mkdir -p "$R"; }

# conf_get KEY [DEFAULT]: value of KEY=VALUE in ultron.conf (no sourcing).
conf_get() {
  local key=$1 def=${2:-} line val=""
  if [[ -r "$ULTRON_CONF" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == "$key="* ]] && val=${line#*=}
    done <"$ULTRON_CONF"
  fi
  val=${val%\"} val=${val#\"}
  printf '%s\n' "${val:-$def}"
}

# conf_set KEY VALUE: create or replace KEY=VALUE in ultron.conf.
conf_set() {
  local key=$1 val=$2 tmp
  mkdir -p "${ULTRON_CONF%/*}"
  touch "$ULTRON_CONF"
  tmp=$(mktemp)
  grep -v "^$key=" "$ULTRON_CONF" >"$tmp" || true
  printf '%s=%s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" "$ULTRON_CONF"
}

boss_kind() { conf_get BOSS omp; }

jocasta_data_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/jocasta/data"; }
jocasta_running() { pgrep -x jocasta >/dev/null 2>&1; }

# ntfy_load: sets NTFY_URL/NTFY_TOKEN/NTFY_PUBLIC from /etc/ultron/ntfy.env; returns 1 if unreadable.
ntfy_load() {
  [[ -r "$NTFY_ENV" ]] || return 1
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case $line in
    NTFY_URL=*) NTFY_URL=${line#*=} ;;
    NTFY_TOKEN=*) NTFY_TOKEN=${line#*=} ;;
    NTFY_PUBLIC=*) NTFY_PUBLIC=${line#*=} ;;
    esac
  done <"$NTFY_ENV"
  [[ -n "${NTFY_URL:-}" && -n "${NTFY_TOKEN:-}" ]]
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

# sway_ids JQ_FILTER: con_ids of tree nodes matching the jq select filter, newest last.
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

desktop_notify() { notify-send -a ultron "$@" 2>/dev/null || true; }

# sudo_keepalive: ask once, refresh in the background until this shell exits.
sudo_keepalive() {
  sudo -v || die "sudo failed"
  (while kill -0 "$$" 2>/dev/null; do
    sudo -n -v 2>/dev/null || true
    sleep 30
  done) &
  _ULTRON_SUDO_PID=$!
  trap 'kill "$_ULTRON_SUDO_PID" 2>/dev/null || true' EXIT
}

# list_packages FILE...: package names from list files (comments and blanks stripped).
list_packages() { sed -e 's/#.*//' -e 's/[[:space:]]\+/\n/g' "$@" | sed '/^$/d'; }
