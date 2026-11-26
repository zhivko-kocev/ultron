#!/usr/bin/env bash
# Pickers: emoji-test.txt lines become "EMOJI NAME" (fully-qualified only), one RGB pixel becomes #rrggbb.
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
echo "pick ok"
