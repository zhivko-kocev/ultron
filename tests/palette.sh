#!/usr/bin/env bash
# Jocasta's palette and the bar: dim text is the theme's MUTED unless it is under 3:1 on the background
# (BG_ALT for Jocasta, BG for the bar), then FG_DIM.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export ULTRON_ROOT=$PWD XDG_RUNTIME_DIR=$HOME/run
# shellcheck source=../lib/common.sh
source lib/common.sh
# shellcheck source=../lib/cmd/apply.sh
source lib/cmd/apply.sh
fail() {
  echo "FAIL palette: $*"
  exit 1
}
mkdir -p "$HOME/.jocasta/agent"
# theme WANT: the colour fg-3 and comment must get.
check() {
  theme_load "$1"
  _apply_palette Mono
  local got
  got=$(jq -r '[.colors["fg-3"], .colors.comment] | join(" ")' "$HOME/.jocasta/agent/palette.json")
  [[ "$got" == "#$2 #$2" ]] || fail "$1: fg-3 and comment are $got, want #$2"
}
check nord d8dee9         # MUTED 4c566a on 3b4252 is 1.3:1
check gruvbox-dark 928374 # MUTED 928374 on 3c3836 is 3.2:1
# The bar: theme WANT: the MUTED line `ultron apply` writes for the bar.
export ULTRON_GEN=$HOME/gen
mkdir -p "$ULTRON_GEN"
bar() {
  theme_load "$1"
  _render templates/colors.tmpl "$ULTRON_GEN/colors" "BAR_MUTED=$(_apply_dim "${_THEME[BG]}")"
  grep -qx "MUTED=#$2" "$ULTRON_GEN/colors" || fail "$1: the bar's MUTED isn't #$2: $(grep MUTED= "$ULTRON_GEN/colors")"
}
bar nord d8dee9         # MUTED 4c566a on 2e3440 is 1.7:1
bar gruvbox-dark 928374 # MUTED 928374 on 282828 is 4.0:1
_contrast_ok 777777 ffffff || fail "#777777 on white is 4.5:1"
if _contrast_ok 999999 ffffff; then fail "#999999 on white is 2.8:1"; fi
echo "palette ok"
