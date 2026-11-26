# shellcheck shell=bash
# ultron dev list|add|remove [TOOL]: programming languages and toolchains, installed for your
# user through mise (no root, no system packages). New terminals pick them up.

_DEV_TOOLS=(node bun deno python go rust java ruby php elixir zig dotnet)

# _dev_installed: "TOOL<TAB>VERSION" for every global mise tool.
_dev_installed() {
  mise ls --global --json 2>/dev/null | jq -r 'to_entries[] | .key as $k
    | (.value | if type == "array" then . else [.] end)[]
    | select(type == "object" and .installed != false)
    | "\($k)\t\(.version // "?")"' 2>/dev/null || true
}

# _dev_version TOOL: the installed version, or empty.
_dev_version() {
  _dev_installed | awk -F '\t' -v t="$1" '$1 == t { print $2; exit }'
}

_dev_need_mise() {
  have mise || die "mise is missing: run 'ultron install packages'"
}

_dev_check_name() {
  [[ "$1" =~ ^[A-Za-z0-9@:/._][A-Za-z0-9@:/._-]*$ ]] || die "'$1' isn't a tool name. Known: ${_DEV_TOOLS[*]}"
}

_dev_list() {
  local name v t
  local -A ver=() known=()
  while IFS=$'\t' read -r name v; do
    if [[ -n "$name" && -z "${ver[$name]-}" ]]; then ver[$name]=$v; fi
  done < <(_dev_installed)
  for t in "${_DEV_TOOLS[@]}"; do
    known[$t]=1
    if [[ -n "${ver[$t]-}" ]]; then
      printf '%-8s ✓ %s\n' "$t" "${ver[$t]}"
    else
      printf '%s\n' "$t"
    fi
  done
  # Tools added some other way (your dotfiles, mise use -g) are listed too, so they can be removed.
  while read -r t; do
    if [[ -n "$t" && -z "${known[$t]-}" ]]; then printf '%-8s ✓ %s\n' "$t" "${ver[$t]}"; fi
  done < <(printf '%s\n' "${!ver[@]}" | sort)
}

_dev_add() {
  local tool=$1 v
  _dev_check_name "$tool"
  say "Installing the latest $tool for your user (this can take a few minutes)…"
  # mise_gh: many tools download from GitHub, which rate-limits anonymous requests.
  mise_gh use -g "$tool@latest" ||
    die "mise could not install '$tool'. Check the name with 'mise registry | grep -i $tool'; if GitHub limited the download, sign in with 'gh auth login' and try again"
  v=$(_dev_version "$tool")
  ok "$tool ${v:-(latest)} installed. New terminals pick it up; in this one, run: exec \$SHELL"
}

_dev_remove() {
  local tool=$1
  _dev_check_name "$tool"
  [[ -n "$(_dev_version "$tool")" ]] || die "$tool isn't one of your global tools (see 'ultron dev list')"
  say "Removing $tool from your global tools…"
  mise unuse -g "$tool" || die "mise could not remove '$tool' (read its message above)"
  # unuse only edits the config: drop the versions nothing else asks for, and their commands.
  # Tools ultron itself pins system-wide (node for the agents) stay installed.
  if ! grep -qsE "^[[:space:]]*\"?${tool}\"?[[:space:]]*=" /etc/mise/conf.d/ultron-tools.toml; then
    mise prune -y "$tool" >/dev/null 2>&1 || true
  fi
  mise reshim
  ok "$tool removed. New terminals no longer have it"
}

cmd_dev() {
  local sub=${1:-list}
  _dev_need_mise
  case $sub in
  list) _dev_list ;;
  add)
    [[ -n "${2:-}" ]] || die "usage: ultron dev add TOOL   (known: ${_DEV_TOOLS[*]}; any mise tool works)"
    _dev_add "$2"
    ;;
  remove)
    [[ -n "${2:-}" ]] || die "usage: ultron dev remove TOOL"
    _dev_remove "$2"
    ;;
  *) die "usage: ultron dev list | add TOOL | remove TOOL" ;;
  esac
}
