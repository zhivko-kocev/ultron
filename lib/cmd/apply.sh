# shellcheck shell=bash
# ultron apply [--no-reload]: render the theme and settings into the app configs, then reload sway
# and mako. Templates are in $ULTRON_ROOT/templates; user overrides in ~/.config/ultron are kept.

# First line of every rendered file; a file without it was written by someone else and is backed up.
# shellcheck disable=SC2016 # the backticks are literal text
_APPLY_MARK='# Written by `ultron apply`'

# _apply_overrides: the per-app override files, created once with a comment and never overwritten.
_apply_overrides() {
  local d=$ULTRON_CONF_DIR name
  local -A what=(
    [foot.ini]="foot settings, read after ultron's (foot.ini format, start with a [section])"
    [fuzzel.ini]="fuzzel settings, read after ultron's (fuzzel.ini format, start with a [section])"
    [mako]="mako global settings, read after ultron's (no [criteria] sections here)"
    [swaylock]="swaylock settings, appended to ~/.config/swaylock/config"
    [gtk.ini]="GTK settings, appended to the [Settings] section of gtk-3.0 and gtk-4.0 settings.ini"
  )
  mkdir -p "$d"/{conf.d,sway,themes,hooks,generated}
  for name in "${!what[@]}"; do
    if [[ ! -e "$d/$name" && ! -L "$d/$name" ]]; then
      printf '# Your %s\n' "${what[$name]}" >"$d/$name"
    fi
  done
}

# _apply_write DEST: stdin into DEST atomically. A symlink (left by old stow packages) is replaced;
# a real file that ultron didn't write is moved to ~/.ultron-backup first.
_apply_write() {
  local dest=$1 dir tmp first="" backup
  dir=$(dirname "$dest")
  mkdir -p "$dir"
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  elif [[ -f "$dest" ]]; then
    IFS= read -r first <"$dest" || true
    if [[ "$first" != "$_APPLY_MARK"* ]]; then
      backup="$HOME/.ultron-backup/$(date -u +%Y%m%dT%H%M%SZ)/${dest#"$HOME"/}"
      mkdir -p "$(dirname "$backup")"
      mv "$dest" "$backup"
      warn "moved your $dest to $backup (ultron writes this file now; put changes in $ULTRON_CONF_DIR)"
    fi
  fi
  tmp=$(mktemp "$dir/.${dest##*/}.XXXXXX")
  if ! cat >"$tmp"; then
    rm -f "$tmp"
    die "could not write $dest"
  fi
  chmod 644 "$tmp"
  mv -fT "$tmp" "$dest"
}

# _render [--append FILE] SRC DEST [KEY=VALUE...]: SRC with @KEY@ replaced by the theme values and
# the extras, written to DEST (then FILE's content, when given). Dies on any placeholder left over.
_render() {
  local append="" src dest text key kv
  if [[ "${1:-}" == --append ]]; then
    append=$2
    shift 2
  fi
  src=$1 dest=$2
  shift 2
  [[ -r "$src" ]] || die "template $src is missing: is the ultron checkout complete?"
  text=$(<"$src")
  for key in "${!_THEME[@]}"; do
    text=${text//"@$key@"/"${_THEME[$key]}"}
  done
  for kv in "$@"; do
    key=${kv%%=*}
    text=${text//"@$key@"/"${kv#*=}"}
  done
  if [[ "$text" =~ @[A-Z0-9_]+@ ]]; then
    die "$src: no value for ${BASH_REMATCH[0]} (add it to the theme, or fix the template)"
  fi
  {
    printf '%s\n' "$text"
    if [[ -n "$append" && -r "$append" ]]; then cat "$append"; fi
  } | _apply_write "$dest"
}

# _apply_check_theme: every colour must be 6-digit hex, MODE dark or light.
_apply_check_theme() {
  local key file
  file=$(theme_path "$_THEME_LOADED" 2>/dev/null) || file="themes/gruvbox-dark.conf"
  for key in "${!_THEME[@]}"; do
    case $key in
    NAME) ;;
    MODE)
      [[ "${_THEME[$key]}" == dark || "${_THEME[$key]}" == light ]] ||
        die "$file: MODE must be dark or light, not '${_THEME[$key]}'"
      ;;
    *)
      [[ "${_THEME[$key]}" =~ ^[0-9A-Fa-f]{6}$ ]] ||
        die "$file: $key=${_THEME[$key]} isn't a colour (6 hex digits, like 282828)"
      ;;
    esac
  done
}

# _apply_seconds VAR KEY: a whole number of seconds from the settings (VAR), the default when it isn't one.
_apply_seconds() {
  local -n _secs=$1
  conf_var _secs "$2"
  if [[ ! "$_secs" =~ ^[0-9]+$ ]]; then
    warn "$2=$_secs isn't a number of seconds: using $(conf_default "$2")"
    _secs=$(conf_default "$2")
  fi
  _secs=$((10#$_secs))
}

_apply_swayidle() {
  local away lock off
  _apply_seconds away AWAY_AFTER
  _apply_seconds lock LOCK_AFTER
  _apply_seconds off SCREEN_OFF_AFTER
  if ((away == 0)); then
    warn "AWAY_AFTER can't be 0: using $(conf_default AWAY_AFTER)"
    away=$(conf_default AWAY_AFTER)
  fi
  {
    # shellcheck disable=SC2016 # literal backticks
    printf '# Written by `ultron apply` from AWAY_AFTER, LOCK_AFTER and SCREEN_OFF_AFTER. Never edit.\n'
    printf '%s\n' "timeout 2 'touch \"\$XDG_RUNTIME_DIR/ultron/idle2\"' resume 'rm -f \"\$XDG_RUNTIME_DIR/ultron/idle2\"'"
    printf 'timeout %s %s\n' "$away" "'ultron attention --away' resume 'rm -f \"\$XDG_RUNTIME_DIR/ultron/away\"'"
    if ((lock > 0)); then printf 'timeout %s %s\n' "$lock" "'ultron lock'"; fi
    if ((off > 0)); then
      printf 'timeout %s %s\n' "$off" "'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"'"
    fi
    printf '%s\n' "before-sleep 'swaylock -f'" "lock 'ultron lock'"
  } | _apply_write "$ULTRON_GEN/swayidle"
}

# _apply_keyboard LAYOUT_VAR VARIANT_VAR: the KEYBOARD and KEYBOARD_VARIANT settings, checked so they
# can't break the sway config.
_apply_keyboard() {
  local -n _layout=$1 _variant=$2
  conf_var _layout KEYBOARD
  conf_var _variant KEYBOARD_VARIANT
  if [[ ! "$_layout" =~ ^[A-Za-z0-9_,()+:-]+$ ]]; then
    warn "KEYBOARD=$_layout isn't an XKB layout list (like us or us,de): using us"
    _layout=us
  fi
  if [[ -n "$_variant" && ! "$_variant" =~ ^[A-Za-z0-9_,()+:-]+$ ]]; then
    warn "KEYBOARD_VARIANT=$_variant isn't an XKB variant list (like dvorak or ,nodeadkeys): ignored"
    _variant=""
  fi
}

cmd_apply() {
  local reload=1 t=$ULTRON_ROOT/templates d=$ULTRON_CONF_DIR mode dark scheme layout variant block
  case ${1:-} in
  "") ;;
  --no-reload) reload=0 ;;
  *) die "usage: ultron apply [--no-reload]" ;;
  esac

  _apply_overrides
  theme_load
  _apply_check_theme
  mode=${_THEME[MODE]}
  if [[ "$mode" == light ]]; then dark=0 scheme=prefer-light; else dark=1 scheme=prefer-dark; fi

  # Multi-line on purpose: sway ignores the settings of a one-line `{ a; b }` block.
  _apply_keyboard layout variant
  block=$'input type:keyboard {\n  xkb_layout '"$layout"
  if [[ -n "$variant" ]]; then block+=$'\n  xkb_variant '"$variant"; fi
  block+=$'\n}'
  _render "$t/sway.conf.tmpl" "$ULTRON_GEN/sway.conf" "KEYBOARD_BLOCK=$block"
  _render "$t/foot.ini.tmpl" "$ULTRON_GEN/foot.ini"
  _render "$t/fuzzel.ini.tmpl" "$ULTRON_GEN/fuzzel.ini"
  _render "$t/colors.tmpl" "$ULTRON_GEN/colors"
  _apply_swayidle
  _render "$t/mako.tmpl" "$HOME/.config/mako/config"
  _render --append "$d/swaylock" "$t/swaylock.tmpl" "$HOME/.config/swaylock/config"
  _render --append "$d/gtk.ini" "$t/gtk.tmpl" "$HOME/.config/gtk-3.0/settings.ini" "DARK=$dark"
  _render --append "$d/gtk.ini" "$t/gtk.tmpl" "$HOME/.config/gtk-4.0/settings.ini" "DARK=$dark"

  if ((reload)); then
    if in_sway; then
      swaymsg reload >/dev/null || warn "swaymsg reload failed: run 'swaymsg reload' to see the config error"
      if pgrep -x mako >/dev/null 2>&1; then
        makoctl reload || warn "makoctl reload failed: check ~/.config/mako/config and $d/mako"
      fi
    fi
  fi
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" >/dev/null 2>&1 || true

  ok "Applied theme $_THEME_LOADED ($mode), keyboard $layout${variant:+ ($variant)}"
}
