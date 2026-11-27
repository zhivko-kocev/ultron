#!/usr/bin/env bash
# Pickers: emoji-test.txt lines become "EMOJI NAME" (fully-qualified only), one RGB pixel becomes #rrggbb, and the
# colour picker reads the physical pixel under the point from a capture of its whole output at the output's scale.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export ULTRON_ROOT=$PWD XDG_RUNTIME_DIR=$HOME/run
# shellcheck source=../lib/common.sh
source lib/common.sh
# shellcheck source=../lib/cmd/pick.sh
source lib/cmd/pick.sh
fail() {
  echo "FAIL pick: $*"
  exit 1
}
cat >"$HOME/emoji-test.txt" <<'EOF'
# group: Smileys & Emotion
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A FE0F                                              ; fully-qualified     # ☺️ E0.6 smiling face
263A                                                   ; unqualified         # ☺ E0.6 smiling face
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
EOF
got=$(_pick_emoji_list "$HOME/emoji-test.txt")
want=$'😀 grinning face\n☺️ smiling face\n👋🏻 waving hand: light skin tone'
[[ "$got" == "$want" ]] || fail "emoji list: got '$got'"
got=$(printf '\xff\x80\x00' | od -An -tx1 | _pick_hex)
[[ "$got" == "#ff8000" ]] || fail "colour: got '$got'"
if printf '\xff\x80' | od -An -tx1 | _pick_hex >/dev/null; then fail "two bytes gave a colour"; fi
# A 4x2 output image; pixel (x, y) has the bytes x, y, 0xaa.
{
  printf 'P6\n4 2\n255\n'
  for y in 0 1; do for x in 0 1 2 3; do printf '%b' "\\x0$x\\x0$y\\xaa"; done; done
} >"$HOME/out.ppm"
[[ $(_pick_ppm_pixel "$HOME/out.ppm" 3 1) == "#0301aa" ]] || fail "ppm pixel 3,1"
if _pick_ppm_pixel "$HOME/out.ppm" 4 0 >/dev/null; then fail "a pixel outside the image gave a colour"; fi
# Output DP-2 at x=100 with scale 1.25: the point 102,1 is physical pixel 2,1 (2.5 and 1.25 rounded down).
slurp() { echo "102,1 1x1"; }
swaymsg() { echo '[{"name":"DP-1","active":true,"scale":1,"rect":{"x":0,"y":0,"width":100,"height":50}},
  {"name":"DP-2","active":true,"scale":1.25,"rect":{"x":100,"y":0,"width":4,"height":2}}]'; }
grim() { [[ "$*" == "-o DP-2 -s 1.25 -t ppm "* ]] || fail "grim $*"; cp "$HOME/out.ppm" "${!#}"; }
wl-copy() { cat >"$HOME/copied"; }
desktop_notify() { :; }
_pick_color
[[ $(<"$HOME/copied") == "#0201aa" ]] || fail "colour picker copied $(<"$HOME/copied")"
echo "pick ok"
