# shellcheck shell=bash
# ultron theme [NAME | --list]: switch the colour theme of sway, the bar, terminals, menus,
# notifications, the lock screen and GTK apps.

_theme_list() {
  local cur name
  conf_var cur THEME
  while IFS= read -r name; do
    if [[ "$name" == "$cur" ]]; then printf '* %s\n' "$name"; else printf '  %s\n' "$name"; fi
  done < <(theme_names)
}

_theme_usage() {
  printf 'usage: ultron theme NAME | --list\nYour own themes go in %s/themes/NAME.conf (copy one from %s/themes).\n' \
    "$ULTRON_CONF_DIR" "$ULTRON_ROOT"
}

cmd_theme() {
  local name=${1:-} msg="Open terminals keep their old colours until you reopen them."
  case $name in
  --list)
    _theme_list
    return 0
    ;;
  -h | --help)
    _theme_usage
    return 0
    ;;
  "")
    if ! in_sway; then
      _theme_list
      _theme_usage
      return 0
    fi
    name=$(theme_names | pick theme) || return 0
    [[ -n "$name" ]] || return 0
    ;;
  esac
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "'$name' isn't a theme name. Themes: $(theme_names | tr '\n' ' ')"
  theme_path "$name" >/dev/null || die "no theme named '$name'. Themes: $(theme_names | tr '\n' ' ')"
  say "Switching to theme $name"
  conf_set THEME "$name"
  # shellcheck source=apply.sh
  source "$ULTRON_ROOT/lib/cmd/apply.sh"
  cmd_apply
  say "$msg"
  if [[ ! -t 1 ]]; then desktop_notify "Theme: $name" "$msg"; fi
}
