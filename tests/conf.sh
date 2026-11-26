#!/usr/bin/env bash
# Settings: conf.d files in name order, ultron.conf last (it wins), quotes and spaces dropped, an empty value
# means the default, and `conf_set KEY ""` removes the line.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export ULTRON_ROOT=$PWD XDG_RUNTIME_DIR=$HOME/run
# shellcheck source=../lib/common.sh
source lib/common.sh
c=$HOME/.config/ultron
mkdir -p "$c/conf.d"
printf 'THEME=nord\nBOSS = "claude --x"\n' >"$c/conf.d/10-a.conf"
printf "THEME='tokyo-night' \n" >"$c/conf.d/20-b.conf"
printf 'BOSS=codex\r\nASK_MODEL=\n' >"$c/ultron.conf"
is() {
  local v
  v=$(conf_get "$1")
  [[ $v == "$2" ]] || {
    echo "FAIL conf: $1='$v', want '$2'"
    exit 1
  }
}
is THEME tokyo-night
is BOSS codex
is ASK_MODEL qwen3:4b
is LOCK_AFTER 600
conf_set BOSS ""
is BOSS "claude --x"
grep -q '^BOSS' "$c/ultron.conf" && {
  echo "FAIL conf: conf_set BOSS \"\" left the line"
  exit 1
}
conf_set THEME gruvbox-light
is THEME gruvbox-light
grep -qx 'ASK_MODEL=' "$c/ultron.conf" || {
  echo "FAIL conf: conf_set dropped another line"
  exit 1
}
echo "conf ok"
