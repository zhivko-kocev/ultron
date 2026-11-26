# shellcheck shell=bash
# ultron install [step...]: install or repair the system, one idempotent step at a time.
# Also provides run_steps and the step helpers shared with `ultron update` and `ultron doctor`.

ULTRON_DEFAULT_STEPS=(preflight dotfiles packages hardware aur system boot ai docker desktop agents)
ULTRON_EXTRA_STEPS=(jocasta net ntfy)
# Requested steps always run in this order. net/ntfy come before agents and jocasta, so every root step
# is done (and the sudo ticket dropped) before mise and Jocasta's build run third-party code.
ULTRON_STEP_ORDER=(preflight dotfiles packages hardware aur system boot ai docker desktop net ntfy agents jocasta)
# Steps that use sudo. jocasta is left out: it does its one root change itself, then drops the ticket.
ULTRON_ROOT_STEPS=(dotfiles packages hardware aur system boot ai desktop net ntfy)
ULTRON_TOOLS_CONF=/etc/mise/conf.d/ultron-tools.toml
# A Limine kernel entry; Limine 9+ names the kernel `path:` (older: `kernel_path:`).
LIMINE_KERNEL_RE='^[[:space:]]*(kernel_)?path:[[:space:]]*boot\(\)'
# Paths whose content runs as root or shapes the system; local changes there need a yes.
ULTRON_TRUSTED_PATHS=(bin lib system packages install templates themes home bootstrap.sh)

# install_root SRC DEST MODE: copy a file to DEST owned by root (never a symlink).
install_root() { sudo install -D -o root -g root -m "$3" "$1" "$2"; }

# pacman_install [PACMAN_OPTION...] PKG...: official packages, already installed ones skipped.
pacman_install() { sudo pacman -S --needed --noconfirm "$@"; }

# toml_tool_keys FILE: the keys of the [tools] table of a mise TOML file, one per line.
toml_tool_keys() {
  awk -v q="'" '
    /^[[:space:]]*\[/ { in_tools = ($0 ~ /^[[:space:]]*\[tools\][[:space:]]*(#.*)?$/); next }
    !in_tools || /^[[:space:]]*(#|$)/ { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      c = substr(line, 1, 1)
      if (c == "\"" || c == q) {
        line = substr(line, 2)
        key = substr(line, 1, index(line, c) - 1)
      } else {
        key = line
        sub(/[[:space:]]*=.*/, "", key)
      }
      if (key != "") print key
    }' "$1"
}

# omp_pin: the oh-my-pi version pinned in the system mise conf (empty when none).
omp_pin() {
  # First install: the file isn't there yet (sed would fail the pipeline).
  [[ -r "$ULTRON_TOOLS_CONF" ]] || return 0
  sed -n -E 's/^[[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$ULTRON_TOOLS_CONF" | head -n1
}

# jocasta_omp_want: the omp version Jocasta's README says it was checked against (empty when none).
jocasta_omp_want() {
  { grep -oE 'checked against omp [0-9]+(\.[0-9]+)*' "$JOCASTA_DIR/README.md" 2>/dev/null || true; } |
    head -n1 | grep -oE '[0-9]+(\.[0-9]+)*$' || true
}

# set_omp_settings: the omp settings ultron needs; `jocasta setup` and a restored config may reset them,
# so the agents step, the jocasta step and `migrate restore` reapply them.
#  - commit role (LOCAL_AI=yes only): the local model first, then whatever non-local models were there.
#    modelRoles is one record setting (`modelRoles.commit` isn't a key), so it's read, merged, written back.
#  - power.sleepPrevention off: omp's default ("idle") holds a logind idle inhibitor while it runs, and
#    swayidle then turns off every timeout (typing guard, away, lock, screen off). Nothing in ultron
#    suspends on idle, so there is nothing for omp to prevent.
set_omp_settings() {
  have omp || return 0
  local local_ai roles new
  conf_var local_ai LOCAL_AI
  if [[ "$local_ai" == yes ]]; then
    roles=$(omp config get modelRoles 2>/dev/null) || roles='{}'
    if new=$(jq -c --arg m "ollama/$(ask_model)" '
      (. // {}) as $r
      | ([($r.commit // "") | splits("\\s*,\\s*") | select(. != "" and (startswith("ollama/") | not))]) as $rest
      | $r + {commit: ([$m] + $rest | join(", "))}' <<<"$roles" 2>/dev/null); then
      omp config set modelRoles "$new" >/dev/null || warn "couldn't set omp's commit role"
    else
      warn "omp's modelRoles isn't JSON, so the commit role wasn't set"
    fi
  fi
  omp config set power.sleepPrevention off >/dev/null || warn "couldn't turn off omp's idle inhibitor"
}

# confirm_checkout: before the first sudo, make sure the code about to run as root is the committed ultron.
confirm_checkout() {
  local changes answer
  if ! changes=$(git -C "$ULTRON_ROOT" status --porcelain --untracked-files=all --ignored -- "${ULTRON_TRUSTED_PATHS[@]}" 2>&1); then
    changes="(not a git checkout: $changes)"
  fi
  [[ -n "$changes" ]] || return 0
  warn "Local changes in $ULTRON_ROOT:"
  printf '%s\n' "$changes" >&2
  if [[ "${ULTRON_ALLOW_DIRTY:-0}" == 1 ]]; then
    warn "ULTRON_ALLOW_DIRTY=1: using them"
    return 0
  fi
  [[ -t 0 ]] || die "These files differ from the committed ultron and would run as root. Commit or discard them, or set ULTRON_ALLOW_DIRTY=1."
  read -rp "These files differ from the committed ultron and will be used as root. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]] || die "Stopped: nothing was changed."
}

# run_hook NAME: run ~/.config/ultron/hooks/NAME when it's executable; a failure is only a warning.
run_hook() {
  local hook=$ULTRON_CONF_DIR/hooks/$1
  [[ -x "$hook" ]] || return 0
  say "Running your $1 hook ($hook)"
  "$hook" || warn "$hook failed (exit $?)"
}

# run_steps STEP...: source lib/install/<step>.sh and run step_<step>, in the given order.
# With ULTRON_STEP_FILE set, the running step's name is kept in that file (emptied when it's done).
run_steps() {
  local s
  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
  for s in "$@"; do
    say "step: $s"
    if [[ -n "${ULTRON_STEP_FILE:-}" ]]; then printf '%s\n' "$s" >"$ULTRON_STEP_FILE"; fi
    # shellcheck source=/dev/null
    source "$ULTRON_ROOT/lib/install/$s.sh"
    "step_$s"
    if [[ -n "${ULTRON_STEP_FILE:-}" ]]; then : >"$ULTRON_STEP_FILE"; fi
    ok "step $s done"
  done
}

# _install_first_boot: `ultron install --first-boot`, started by the first login on tty1 (bootstrap.sh arms
# it): the default steps, then a reboot into the desktop. A failure names the step and returns to the shell;
# the first-boot files stay until the desktop step removes them, so until then each login on tty1 retries.
_install_first_boot() {
  local step_file step
  # The autologin is quicker than NetworkManager joining the Wi-Fi network bootstrap.sh carried over.
  nm-online -q -t 30 >/dev/null 2>&1 || true
  step_file=$(mktemp)
  # A child process, so a failing step stops the install (set -e is off inside an `if` condition).
  if ULTRON_STEP_FILE=$step_file "$ULTRON_ROOT/bin/ultron" install; then
    rm -f "$step_file"
    say "Starting the desktop in 10 s (Ctrl+C to stay here)"
    sleep 10
    systemctl reboot
    return 0
  fi
  step=$(cat "$step_file")
  rm -f "$step_file"
  echo
  warn "The install stopped${step:+ in step $step} (the error is above)."
  if ! curl -fsI --max-time 10 https://archlinux.org >/dev/null 2>&1; then
    echo "No internet: run nmtui, pick 'Activate a connection' and join your network, then run: ultron install --first-boot"
  else
    echo "Fix it, then run: ultron install --first-boot"
  fi
  return 1
}

cmd_install() {
  local s steps=() last_root=""
  if [[ "${1:-}" == --first-boot ]]; then
    (($# == 1)) || die "--first-boot runs the default steps: give it no step names."
    _install_first_boot
    return
  fi
  for s in "$@"; do
    _in_list "$s" "${ULTRON_STEP_ORDER[@]}" ||
      die "unknown step '$s'. Steps: ${ULTRON_DEFAULT_STEPS[*]}; on demand: ${ULTRON_EXTRA_STEPS[*]}"
  done
  ((EUID != 0)) || die "Run ultron install as your user, not root: it uses sudo when it needs to."
  for s in "${ULTRON_STEP_ORDER[@]}"; do
    if (($#)); then
      _in_list "$s" "$@" || continue
    else
      _in_list "$s" "${ULTRON_DEFAULT_STEPS[@]}" || continue
    fi
    steps+=("$s")
    if _in_list "$s" "${ULTRON_ROOT_STEPS[@]}" jocasta; then last_root=$s; fi
  done
  say "Running: ${steps[*]}"
  if [[ -n "$last_root" ]]; then
    confirm_checkout
    if [[ "$last_root" != jocasta ]]; then sudo_keepalive; fi
  fi
  for s in "${steps[@]}"; do
    run_steps "$s"
    if [[ "$s" == "$last_root" ]]; then sudo_drop; fi
  done
  if ((!$#)); then
    "$ULTRON_ROOT/bin/ultron" doctor || die "doctor found problems (the FAIL lines above); fix them and rerun: ultron doctor"
  fi
  run_hook post-install
  # Under --first-boot (ULTRON_STEP_FILE set) the parent reboots by itself.
  if [[ -z "${ULTRON_STEP_FILE:-}" ]] && ! systemctl is-active -q greetd; then
    say "Reboot to start the desktop"
  fi
}
