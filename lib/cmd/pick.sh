# shellcheck shell=bash
# ultron pick clip|emoji|color|font|background: pickers in fuzzel.
#   clip        clipboard history (Super+Ctrl+V)
#   emoji       an emoji, copied and typed (Super+Ctrl+E)
#   color       the colour of one pixel you click, copied as #rrggbb
#   font        the font of terminals, launcher, notifications and bar (FONT)
#   background  the image behind the windows (BACKGROUND), from ~/.config/ultron/backgrounds and ~/Pictures

ULTRON_EMOJI_FILE=${ULTRON_EMOJI_FILE:-/usr/share/unicode/emoji/emoji-test.txt}

# _pick_emoji_list FILE: "EMOJI NAME" for every fully-qualified emoji in Unicode's emoji-test.txt.
# Its lines: `1F600 ; fully-qualified # 😀 E1.0 grinning face`.
_pick_emoji_list() {
  awk '/; fully-qualified[[:space:]]+#/ {
    sub(/^[^#]*# /, "")
    e = $1
    sub(/^[^ ]+ E[0-9.]+ /, "")
    print e " " $0
  }' "$1"
}

# _pick_hex: `od -An -tx1` output of one RGB pixel on stdin -> #rrggbb.
_pick_hex() {
  local hex
  hex=$(tr -d ' \n')
  [[ "$hex" =~ ^[0-9a-f]{6}$ ]] || return 1
  printf '#%s\n' "$hex"
}

_pick_clip() {
  local sel
  sel=$(cliphist list | pick clip) || return 0
  printf '%s' "$sel" | cliphist decode | wl-copy
}

_pick_emoji() {
  local sel e
  [[ -r "$ULTRON_EMOJI_FILE" ]] || die "$ULTRON_EMOJI_FILE is missing: run 'ultron install packages'"
  sel=$(_pick_emoji_list "$ULTRON_EMOJI_FILE" | pick emoji) || return 0
  e=${sel%% *}
  printf '%s' "$e" | wl-copy
  wtype -- "$e" 2>/dev/null || true
}

# _pick_ppm_pixel FILE X Y: the RGB bytes at pixel X,Y of grim's binary PPM (header "P6\nW H\n255\n") as #rrggbb.
_pick_ppm_pixel() {
  local magic w h hlen
  { read -r magic && read -r w h; } <"$1" || return 1
  [[ "$magic" == P6 && "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] && (($2 < w && $3 < h)) || return 1
  hlen=$(head -n 3 -- "$1" | wc -c)
  od -An -tx1 -j $((hlen + ($3 * w + $2) * 3)) -N 3 -- "$1" | _pick_hex
}

# The whole output under the point is captured at its own scale: grim's image is then the output's pixels 1:1.
# A 1x1 region (or another scale) makes grim resample, and at a fractional scale the region starts between two
# physical pixels, so its bilinear filter mixes in the neighbours (#fabd2f came out #f9be34 at 1.25).
_pick_color() {
  local point x y out name="" scale ox oy="" px py tmp hex=""
  point=$(slurp -p) || return 0 # "X,Y 1x1" in layout coordinates
  [[ "$point" =~ ^(-?[0-9]+),(-?[0-9]+) ]] || die "slurp gave an unexpected point: $point"
  x=${BASH_REMATCH[1]} y=${BASH_REMATCH[2]}
  out=$(swaymsg -t get_outputs | jq -r --argjson x "$x" --argjson y "$y" 'first(.[] | select(.active and
    .rect.x <= $x and $x < .rect.x + .rect.width and .rect.y <= $y and $y < .rect.y + .rect.height) |
    "\(.name) \(.scale) \(.rect.x) \(.rect.y)")') || true
  read -r name scale ox oy <<<"$out"
  [[ -n "$oy" ]] || die "no output holds the point $x,$y"
  read -r px py < <(awk -v x=$((x - ox)) -v y=$((y - oy)) -v s="$scale" \
    'BEGIN { printf "%d %d\n", x * s + 1e-6, y * s + 1e-6 }')
  tmp=$(mktemp "${TMPDIR:-/tmp}/ultron-pick.XXXXXX")
  if grim -o "$name" -s "$scale" -t ppm "$tmp"; then hex=$(_pick_ppm_pixel "$tmp" "$px" "$py") || hex=""; fi
  rm -f "$tmp"
  [[ -n "$hex" ]] || die "couldn't read the colour under the pointer"
  printf '%s' "$hex" | wl-copy
  desktop_notify "Colour $hex" "Copied"
}

# _pick_apply KEY VALUE TITLE [BODY]: save the setting, apply it, and say so.
_pick_apply() {
  local out
  conf_set "$1" "$2"
  if out=$("$ULTRON_ROOT/bin/ultron" apply 2>&1); then
    desktop_notify "$3" "${4:-}"
  else
    desktop_notify -u critical "ultron apply: something went wrong" "$(tail -n 4 <<<"$out")"
  fi
}

_pick_font() {
  local f
  f=$(fc-list :spacing=100 family | cut -d, -f1 | sort -u | pick font) || return 0
  _pick_apply FONT "$f" "Font: $f" "New terminals use it; open windows keep their font"
}

_pick_background() {
  local sel dirs=() d
  for d in "$ULTRON_CONF_DIR/backgrounds" "$HOME/Pictures"; do
    if [[ -d "$d" ]]; then dirs+=("$d"); fi
  done
  sel=$({
    printf 'None\n'
    if ((${#dirs[@]})); then
      find "${dirs[@]}" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
        -o -iname '*.webp' \) | sort
    fi
  } | pick background) || return 0
  if [[ "$sel" == None ]]; then
    _pick_apply BACKGROUND "" "Background: the theme's colour"
  else
    _pick_apply BACKGROUND "$sel" "Background: ${sel##*/}"
  fi
}

cmd_pick() {
  case ${1:-} in
  clip) _pick_clip ;;
  emoji) _pick_emoji ;;
  color) _pick_color ;;
  font) _pick_font ;;
  background) _pick_background ;;
  *) die "usage: ultron pick clip|emoji|color|font|background" ;;
  esac
}
