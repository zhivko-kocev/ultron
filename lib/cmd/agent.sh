# shellcheck shell=bash
# ultron agent: agent CLIs from agents/registry.tsv (and ~/.config/ultron/agents.tsv).
#   agent list                 NAME, installed|missing, and which one is the boss
#   agent add NAME             install it with mise and teach it about ultron
#   agent remove NAME          uninstall it and remove what add wrote
#   agent run NAME [ARGS...]   run it with ultron's sudo popup
#   agent boss NAME            make it the boss (the window on workspace 1)

_AGENT_SKILL="$HOME/.agents/skills/ultron"
_AGENT_BEGIN="<!-- ultron:begin -->"
_AGENT_END="<!-- ultron:end -->"

declare -A _AG_TOOL=() _AG_BIN=() _AG_GUIDE=()
_AG_NAMES=()

# _agent_load: the registry, then the user's file; a later line wins by name.
_agent_load() {
  local f name tool bin guide
  for f in "$ULTRON_ROOT/agents/registry.tsv" "$ULTRON_CONF_DIR/agents.tsv"; do
    [[ -r "$f" ]] || continue
    while IFS=$'\t' read -r name tool bin guide || [[ -n "$name" ]]; do
      [[ -n "$name" && "$name" != \#* ]] || continue
      if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || -z "$tool" || -z "$bin" ]]; then
        warn "$f: skipping a line without name, mise tool and binary: $name"
        continue
      fi
      [[ -n "${_AG_BIN[$name]-}" ]] || _AG_NAMES+=("$name")
      _AG_TOOL[$name]=$tool
      _AG_BIN[$name]=$bin
      _AG_GUIDE[$name]=${guide:--}
    done <"$f"
  done
}

_agent_known() {
  [[ -n "${_AG_BIN[$1]-}" ]] ||
    die "unknown agent '$1'. Known: ${_AG_NAMES[*]}. Add your own to $ULTRON_CONF_DIR/agents.tsv (see docs/agents.md)"
}

# _agent_path P: ~/ expanded.
_agent_path() { printf '%s\n' "${1/#\~/$HOME}"; }

_agent_boss_bin() {
  local boss
  read -r boss _ <<<"$(boss_kind)"
  printf '%s\n' "$boss"
}

cmd_agent() {
  local sub=${1:-}
  shift || true
  _agent_load
  case $sub in
  list) _agent_list ;;
  add) _agent_add "$@" ;;
  remove) _agent_remove "$@" ;;
  run) _agent_run "$@" ;;
  boss) _agent_boss "$@" ;;
  *) die "usage: ultron agent list | add NAME | remove NAME | run NAME [ARGS...] | boss NAME" ;;
  esac
}

_agent_list() {
  local name state boss
  boss=$(_agent_boss_bin)
  for name in "${_AG_NAMES[@]}"; do
    state=missing
    if have "${_AG_BIN[$name]}"; then state=installed; fi
    if [[ "${_AG_BIN[$name]}" == "$boss" ]]; then
      printf '%s\t%s\tboss\n' "$name" "$state"
    else
      printf '%s\t%s\t\n' "$name" "$state"
    fi
  done
}

_agent_add() {
  local name=${1:-}
  [[ -n "$name" ]] || die "usage: ultron agent add NAME (see: ultron agent list)"
  _agent_known "$name"
  if [[ "$name" == omp ]]; then
    say "omp ships with ultron: it's installed by 'ultron install agents' and already reads the ultron skill"
    return 0
  fi
  local tool=${_AG_TOOL[$name]} bin=${_AG_BIN[$name]}

  if [[ "$tool" != - ]]; then
    have mise || die "mise isn't installed: run 'ultron install packages agents' first"
    say "Installing $name ($tool) with mise"
    mise_gh use -g "$tool@latest" || die "mise couldn't install $tool (try: mise use -g $tool@latest)"
    mise reshim
  fi
  local version run=()
  if [[ "$tool" != - ]]; then run=(mise exec --); fi
  version=$("${run[@]}" "$bin" --version 2>/dev/null | awk 'NR == 1') ||
    die "$name is installed but '$bin --version' fails; check it in a terminal: $bin --version"
  ok "$name ${version:-installed}"

  _agent_guide_add "$name"

  cat <<EOF

Next:
  ultron agent run $name     start it in a terminal (its sudo asks through ultron's popup)
  ultron agent boss $name    make it the boss window on workspace 1
To let it call you when it's blocked or done, hook its notifications to
'ultron attention --raise' and '--done': docs/agents.md shows how.
EOF
}

# _agent_guide_add NAME: put the ultron guide where the agent reads global instructions.
_agent_guide_add() {
  local guide=${_AG_GUIDE[$1]} kind target
  kind=${guide%%:*}
  target=$(_agent_path "${guide#*:}")
  case $kind in
  link) _agent_link "$target" ;;
  skills)
    if [[ "$target" != "$HOME/.agents/skills" ]]; then _agent_link "$target/ultron"; fi
    ;;
  block) _agent_block_write "$target" ;;
  -) ;;
  *) warn "$1: unknown guide '$guide' (use skills:DIR, link:DIR, block:FILE or -)" ;;
  esac
}

# _agent_link DIR: DIR becomes a link to the ultron skill. Only a link is ever replaced.
_agent_link() {
  local dir=$1
  [[ -d "$_AGENT_SKILL" ]] || warn "$_AGENT_SKILL is missing; run 'ultron install desktop' to create it"
  if [[ -e "$dir" && ! -L "$dir" ]]; then
    warn "$dir exists and isn't a link; left alone. Remove it and rerun to use the ultron guide"
    return 0
  fi
  mkdir -p "$(dirname -- "$dir")"
  ln -sfn "$_AGENT_SKILL" "$dir"
  ok "linked $dir -> $_AGENT_SKILL"
}

# _agent_block_strip FILE: FILE's text without the ultron block.
_agent_block_strip() {
  awk -v b="$_AGENT_BEGIN" -v e="$_AGENT_END" '$0 == b {skip = 1; next} skip && $0 == e {skip = 0; next} !skip' "$1"
}

# _agent_block_write FILE: add or replace the ultron block; the rest of the file stays as it was.
_agent_block_write() {
  local file=$1 rest
  local block="$_AGENT_BEGIN
This PC runs ultron (Arch + sway).
Run \`ultron guide\` and follow it before opening windows for the user, using sudo, or using the local model.
$_AGENT_END"
  mkdir -p "$(dirname -- "$file")"
  if [[ -e "$file" ]] && grep -qxF "$_AGENT_BEGIN" "$file"; then
    grep -qxF "$_AGENT_END" "$file" || die "$file: the ultron block has no end line; fix it by hand"
    # Replace in place, so the block keeps its position.
    rest=$(BLOCK=$block awk -v b="$_AGENT_BEGIN" -v e="$_AGENT_END" '
      $0 == b {print ENVIRON["BLOCK"]; skip = 1; next}
      skip && $0 == e {skip = 0; next}
      !skip' "$file")
    # Written through the path, so a stow link stays a link.
    printf '%s\n' "$rest" >"$file"
  elif [[ -s "$file" ]]; then
    printf '\n%s\n' "$block" >>"$file"
  else
    printf '%s\n' "$block" >"$file"
  fi
  ok "ultron block in $file"
}

_agent_remove() {
  local name=${1:-}
  [[ -n "$name" ]] || die "usage: ultron agent remove NAME"
  _agent_known "$name"
  [[ "$name" != omp ]] || die "omp ships with ultron and can't be removed (pick another boss: ultron agent boss NAME)"
  local tool=${_AG_TOOL[$name]} bin=${_AG_BIN[$name]} guide=${_AG_GUIDE[$name]} target was_boss=0
  if [[ "$(_agent_boss_bin)" == "$bin" ]]; then was_boss=1; fi

  if [[ "$tool" != - ]]; then
    have mise || die "mise isn't installed, so there's nothing it could remove"
    say "Removing $name ($tool)"
    mise unuse -g "$tool" || die "mise couldn't remove $tool (try: mise unuse -g $tool)"
    # unuse only edits the config: drop the installed copy and its command too.
    mise prune -y "$tool" >/dev/null 2>&1 || true
    mise reshim
  else
    warn "$name wasn't installed by mise; uninstall '$bin' the way you installed it"
  fi

  target=$(_agent_path "${guide#*:}")
  case ${guide%%:*} in
  link) _agent_unlink "$target" ;;
  skills)
    if [[ "$target" != "$HOME/.agents/skills" ]]; then _agent_unlink "$target/ultron"; fi
    ;;
  block)
    if [[ -f "$target" ]] && grep -qxF "$_AGENT_BEGIN" "$target"; then
      grep -qxF "$_AGENT_END" "$target" || die "$target: the ultron block has no end line; fix it by hand"
      local rest
      rest=$(_agent_block_strip "$target")
      printf '%s\n' "$rest" >"$target"
      ok "removed the ultron block from $target"
    fi
    ;;
  esac

  if ((was_boss)); then
    conf_set BOSS ""
    say "$name was the boss; the boss is $(conf_get BOSS) again. Close the boss window (Super+W on workspace 1), then press Super+B"
  fi
  ok "$name removed"
}

# _agent_unlink DIR: remove DIR only when it is our link to the skill.
_agent_unlink() {
  if [[ -L "$1" && "$(readlink -- "$1")" == "$_AGENT_SKILL" ]]; then
    rm -f -- "$1"
    ok "removed link $1"
  fi
}

_agent_run() {
  local name=${1:-}
  [[ -n "$name" ]] || die "usage: ultron agent run NAME [ARGS...]"
  shift
  local bin=${_AG_BIN[$name]-$name}
  have "$bin" || die "'$bin' isn't installed (try: ultron agent add $name)"
  [[ -x "$AGENT_BIN/sudo" ]] || warn "$AGENT_BIN/sudo is missing, so sudo prompts in the terminal; run 'ultron install desktop'"
  exec env PATH="$AGENT_BIN:$PATH" "$bin" "$@"
}

_agent_boss() {
  local name=${1:-}
  [[ -n "$name" ]] || die "usage: ultron agent boss NAME"
  local bin=${_AG_BIN[$name]-$name}
  have "$bin" || die "'$bin' isn't installed (try: ultron agent add $name)"
  conf_set BOSS "$bin"
  ok "the boss is now $bin"
  say "Close the boss window (Super+W on workspace 1), then press Super+B to start $bin there"
}
