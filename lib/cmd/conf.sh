# shellcheck shell=bash
# ultron conf [list | get KEY | set KEY VALUE | edit | path]: this machine's settings.

_conf_list() {
  local k v d
  conf_load
  for k in "${_CONF_KEYS[@]}"; do
    conf_var v "$k"
    d=${_CONF_DEFAULT[$k]-}
    if [[ "$v" == "$d" ]]; then
      printf '%-18s %s\n' "$k" "${v:-(empty)}"
    else
      printf '%-18s %s   (default: %s)\n' "$k" "$v" "${d:-empty}"
    fi
  done
}

cmd_conf() {
  local sub=${1:-list}
  case $sub in
  list) _conf_list ;;
  path) printf '%s\n' "$ULTRON_CONF" ;;
  get)
    [[ -n "${2:-}" ]] || die "usage: ultron conf get KEY"
    _in_list "$2" "${_CONF_KEYS[@]}" || die "unknown setting '$2'. Settings: ${_CONF_KEYS[*]}"
    conf_get "$2"
    ;;
  set)
    (($# == 3)) || die "usage: ultron conf set KEY VALUE   (\"\" as VALUE goes back to the default)"
    _in_list "$2" "${_CONF_KEYS[@]}" || die "unknown setting '$2'. Settings: ${_CONF_KEYS[*]}"
    conf_set "$2" "$3"
    ok "$2=$(conf_get "$2")"
    # shellcheck source=apply.sh
    source "$ULTRON_ROOT/lib/cmd/apply.sh"
    cmd_apply
    ;;
  edit)
    mkdir -p "$ULTRON_CONF_DIR"
    [[ -e "$ULTRON_CONF" ]] || : >"$ULTRON_CONF"
    ${EDITOR:-nano} "$ULTRON_CONF"
    # shellcheck source=apply.sh
    source "$ULTRON_ROOT/lib/cmd/apply.sh"
    cmd_apply
    ;;
  *) die "usage: ultron conf [list | get KEY | set KEY VALUE | edit | path]" ;;
  esac
}
