# shellcheck shell=bash
# ultron install [step...]: install or repair the system, one idempotent step at a time.
# Also provides run_steps and shared step helpers for `ultron update`.

ULTRON_DEFAULT_STEPS=(preflight pacman packages aur system boot desktop agents docker ai dotfiles verify)
ULTRON_EXTRA_STEPS=(jocasta net ntfy)
ULTRON_TOOLS_CONF=/etc/mise/conf.d/ultron-tools.toml

# install_root SRC DEST MODE: copy a file to DEST owned by root (never a symlink).
install_root() { sudo install -D -o root -g root -m "$3" "$1" "$2"; }

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
  sed -n -E 's/^[[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$ULTRON_TOOLS_CONF" 2>/dev/null | head -n1
}

# set_commit_role: point omp's commit role at the local model first.
set_commit_role() {
  if have omp; then
    omp config set modelRoles.commit "$OMP_COMMIT_ROLE" || warn "couldn't set omp's commit role"
  else
    warn "omp isn't installed yet, so its commit role wasn't set"
  fi
}

_valid_step() {
  local s
  for s in "${ULTRON_DEFAULT_STEPS[@]}" "${ULTRON_EXTRA_STEPS[@]}"; do
    [[ "$s" == "$1" ]] && return 0
  done
  return 1
}

# run_steps STEP...: source lib/install/<step>.sh and run step_<step>, in order.
run_steps() {
  local s
  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
  for s in "$@"; do
    say "step: $s"
    # shellcheck source=/dev/null
    source "$ULTRON_ROOT/lib/install/$s.sh"
    "step_$s"
    ok "step $s done"
  done
}

cmd_install() {
  local steps=("$@") s
  ((${#steps[@]})) || steps=("${ULTRON_DEFAULT_STEPS[@]}")
  for s in "${steps[@]}"; do
    _valid_step "$s" || die "unknown step '$s'. Steps: ${ULTRON_DEFAULT_STEPS[*]}; on demand: ${ULTRON_EXTRA_STEPS[*]}"
  done
  ((EUID != 0)) || die "Run ultron install as your user, not root: it uses sudo when it needs to."
  say "Running: ${steps[*]}"
  sudo_keepalive
  run_steps "${steps[@]}"
  if ! systemctl is-active -q greetd; then
    say "Reboot to start the desktop"
  fi
}
