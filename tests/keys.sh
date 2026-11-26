#!/usr/bin/env bash
# Keys: `ultron keys` reads the sway config (your files win), and docs/keys.md lists exactly its agentic keys.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export ULTRON_ROOT=$PWD XDG_RUNTIME_DIR=$HOME/run
# shellcheck source=../lib/common.sh
source lib/common.sh
# shellcheck source=../lib/cmd/keys.sh
source lib/cmd/keys.sh
fail() {
  echo "FAIL keys: $*"
  exit 1
}
sway=home/sway/.config/sway/config
mkdir -p "$ULTRON_CONF_DIR/sway"
# shellcheck disable=SC2016 # $mod is sway's variable, not the shell's
printf 'bindsym --no-warn $mod+Shift+f exec nautilus\nbindsym $mod+g exec ultron webapp open github\n' \
  >"$ULTRON_CONF_DIR/sway/keys.conf"
list=$(_keys_list "$sway" "$ULTRON_CONF_DIR/sway/keys.conf")
grep -qxF 'Super+Shift+B — workspace 9:browse; ultron browser · Apps' <<<"$list" || fail "Super+Shift+B line"
grep -qxF 'Super+0 — workspace 10:sys · Workspaces' <<<"$list" || fail "Super+0 line"
grep -qxF 'Super+Shift+F — nautilus · yours' <<<"$list" || fail "an override doesn't replace the key"
grep -qxF 'Super+G — ultron webapp open github · yours' <<<"$list" || fail "a new key of yours is missing"
(($(grep -c '^Super+Shift+F ' <<<"$list") == 1)) || fail "Super+Shift+F listed twice"

want=$(_keys_list "$sway" | sed -n 's/^\([^ ]*\) — .* · Agentic keys$/\1/p' | sort)
got=$(sed -n 's/^| \(Super+[^ |]*\) |.*/\1/p' docs/keys.md | sort)
[[ -n "$want" && "$got" == "$want" ]] || fail "docs/keys.md's agentic keys differ from the sway config: got '$got', want '$want'"
echo "keys ok"
