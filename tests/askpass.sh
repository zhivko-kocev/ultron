#!/usr/bin/env bash
# askpass: the popup text names root shells and root file edits, quotes the command, refuses long ones.
# The real script runs with the sudo command line read from a file and the popup text printed instead of fuzzel.
# shellcheck disable=SC2016 # $mesg is askpass's own variable: it must reach the copy unexpanded.
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run/ultron"
touch "$t/run/ultron/idle2"
for c in notify-send makoctl pgrep curl fuzzel swaymsg; do
  printf '#!/bin/sh\nexit 1\n' >"$t/bin/$c"
  chmod +x "$t/bin/$c"
done
sed -e "s#/proc/[^ ]*cmdline#$t/argv#g" -e 's#^timeout 600 fuzzel.*#printf "%s\\n" "$mesg"#' \
  system/usr/lib/ultron/askpass >"$t/askpass"
grep -q 'printf "%s\\n" "$mesg"' "$t/askpass" || {
  echo "FAIL askpass: the fuzzel line moved; update tests/askpass.sh"
  exit 1
}

pop() {
  printf '%s\0' sudo -k -A "$@" >"$t/argv"
  PATH="$t/bin:$PATH" XDG_RUNTIME_DIR="$t/run" WAYLAND_DISPLAY=wayland-test bash "$t/askpass" 2>&1 || true
}
want() {
  [[ $2 == *"$1"* ]] || {
    printf 'FAIL askpass: want %q in:\n%s\n' "$1" "$2"
    exit 1
  }
}
want 'ROOT SHELL' "$(pop -s)"
want 'ROOT SHELL' "$(pop -u root -s)"
want 'ROOT SHELL' "$(pop -i)"
want 'ROOT SHELL' "$(pop -iu root)"
want 'EDITS A FILE AS ROOT' "$(pop -e /etc/fstab)"
want 'Run as root: touch a\ b' "$(pop touch 'a b')"
want 'too long' "$(pop echo "$(printf 'x%.0s' {1..700})")"
echo "askpass ok"
