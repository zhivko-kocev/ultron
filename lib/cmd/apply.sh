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

# _apply_font VAR: the FONT setting, checked so it can't break the sway, foot, fuzzel or mako config.
_apply_font() {
  local -n _font=$1
  conf_var _font FONT
  if [[ ! "$_font" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._+-]*$ ]]; then
    warn "FONT=$_font isn't a font family name (like JetBrainsMono Nerd Font): using $(conf_default FONT)"
    _font=$(conf_default FONT)
  fi
}

# _apply_background VAR: the sway line for the BACKGROUND setting (an image, ~ allowed), else the theme colour.
_apply_background() {
  local -n _bg=$1
  local file
  conf_var file BACKGROUND
  # shellcheck disable=SC2088 # a literal ~/ in the setting, expanded here
  if [[ "${file:0:2}" == "~/" ]]; then file=$HOME/${file:2}; fi
  _bg="output * bg #${_THEME[BG]} solid_color"
  if [[ -z "$file" ]]; then return 0; fi
  if [[ "$file" == *'"'* || ! -f "$file" ]]; then
    warn "BACKGROUND=$file isn't an image file: using the theme's colour"
    return 0
  fi
  _bg="output * bg \"$file\" fill"
}

# _apply_effects: SwayFX's corners, shadows and animations when EFFECTS=yes and SwayFX is installed; empty
# otherwise (stock sway reports these options as config errors). The sway config includes it.
# When a compositor answers on IPC, it must be SwayFX itself (version 0.x; stock sway is 1.x): right after
# SwayFX is installed, the running stock sway would show a config error until the next login. The session
# script runs `ultron apply` before sway starts, so effects start at the next login.
_apply_effects() {
  local fx on=0 major
  conf_var fx EFFECTS
  if [[ "$fx" == yes ]] && pacman -Q swayfx >/dev/null 2>&1; then
    on=1
    if major=$(swaymsg -t get_version -r 2>/dev/null | jq -r '.major' 2>/dev/null) && [[ -n "$major" ]]; then
      if [[ "$major" != 0 ]]; then on=0; fi
    fi
  fi
  {
    # shellcheck disable=SC2016 # literal backticks
    printf '# Written by `ultron apply` from EFFECTS (on only when SwayFX is installed and running). Never edit.\n'
    if ((on)); then
      printf '%s\n' 'corner_radius 6' 'shadows enable' 'shadow_blur_radius 20' 'shadow_color #00000066' \
        'animation_duration_ms 150' 'blur disable'
    fi
  } | _apply_write "$ULTRON_GEN/effects.conf"
}

# _contrast_ok FG BG: whether two hex colours (no #) have a WCAG contrast ratio of at least 3:1.
_contrast_ok() {
  local c v=()
  for c in "$1" "$2"; do v+=($((16#${c:0:2})) $((16#${c:2:2})) $((16#${c:4:2}))); done
  awk -v s="${v[*]}" 'function lin(c) { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
    function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
    BEGIN { split(s, v, " "); a = lum(v[1], v[2], v[3]); b = lum(v[4], v[5], v[6])
      if (a < b) { t = a; a = b; b = t }
      exit !((a + 0.05) / (b + 0.05) >= 3) }'
}

# _apply_dim BG: the theme's MUTED, or FG_DIM when MUTED is unreadable on BG (under 3:1, as in Nord).
_apply_dim() {
  if _contrast_ok "${_THEME[MUTED]}" "$1"; then echo "${_THEME[MUTED]}"; else echo "${_THEME[FG_DIM]}"; fi
}

# _apply_palette FONT: the theme's colours and the font for Jocasta (~/.jocasta/agent/palette.json, read when
# Jocasta starts), written only when Jocasta is set up. Needs theme_load first; FONT is _apply_font's checked name.
# fg-3 and comment are _apply_dim on BG_ALT.
_apply_palette() {
  local dir=$HOME/.jocasta/agent tmp dim
  [[ -d "$dir" ]] || return 0
  dim=$(_apply_dim "${_THEME[BG_ALT]}")
  tmp=$(mktemp "$dir/.palette.json.XXXXXX")
  printf '{"font": "%s", "colors": {"bg-0": "#%s", "bg-1": "#%s", "bg-2": "#%s", "bg-3": "#%s", "fg": "#%s", "fg-2": "#%s", "fg-3": "#%s", "comment": "#%s", "blue": "#%s", "cyan": "#%s", "yellow": "#%s", "red": "#%s", "green": "#%s", "purple": "#%s", "orange": "#%s"}}\n' \
    "$1" "${_THEME[BG]}" "${_THEME[BG_ALT]}" "${_THEME[BG_ALT]}" "${_THEME[BG_SEL]}" "${_THEME[FG]}" \
    "${_THEME[FG_DIM]}" "$dim" "$dim" "${_THEME[C12]}" "${_THEME[C14]}" "${_THEME[C11]}" \
    "${_THEME[C9]}" "${_THEME[C10]}" "${_THEME[C13]}" "${_THEME[ACCENT_ALT]}" >"$tmp"
  mv -fT "$tmp" "$dir/palette.json"
}

cmd_apply() {
  local reload=1 t=$ULTRON_ROOT/templates d=$ULTRON_CONF_DIR mode dark scheme layout variant block font bg
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
  _apply_font font
  _apply_background bg
  _render "$t/sway.conf.tmpl" "$ULTRON_GEN/sway.conf" "KEYBOARD_BLOCK=$block" "FONT=$font" "BG_LINE=$bg"
  _render "$t/foot.ini.tmpl" "$ULTRON_GEN/foot.ini" "FONT=$font"
  _render "$t/fuzzel.ini.tmpl" "$ULTRON_GEN/fuzzel.ini" "FONT=$font"
  _render "$t/colors.tmpl" "$ULTRON_GEN/colors" "BAR_MUTED=$(_apply_dim "${_THEME[BG]}")"
  _apply_swayidle
  _apply_effects
  _apply_palette "$font"
  _render "$t/mako.tmpl" "$HOME/.config/mako/config" "FONT=$font"
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
