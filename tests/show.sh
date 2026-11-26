#!/usr/bin/env bash
# show: windows land on 2 / 3 / 4 (review pages on 2, the board on 4) without moving the user; the bar marks
# their workspace; the registry lists ids and tags; close by id or tag; attentiond closes tagged windows whose
# folder is gone and moves agents' visible browsers to 3. sway and the apps are stubs over a canned tree.
# shellcheck disable=SC2016 # stub bodies are scripts of their own: their $ must reach the file unexpanded.
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."
t=$(mktemp -d)
fb=""
trap 'if [[ -n $fb ]]; then kill "$fb" 2>/dev/null || true; fi; rm -rf "$t"' EXIT
export T=$t HOME=$t/home XDG_RUNTIME_DIR=$t/run ULTRON_ROOT=$PWD PATH="$t/bin:$PATH"
unset SWAYSOCK ULTRON_TAG JOCASTA_THREAD
R=$XDG_RUNTIME_DIR/ultron
mkdir -p "$t/bin" "$HOME" "$R" "$t/wt1" "$t/wt2"
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$t/bin/$1"
  chmod +x "$t/bin/$1"
}
stub swaymsg 'if [[ $1 == -t ]]; then case $2 in get_tree) cat "$T/tree.json" ;; get_workspaces) cat "$T/ws.json" ;; esac; else echo "$*" >>"$T/sway.log"; fi'
# addwin APP PID WORKSPACE TITLE: a new window in the tree.
stub addwin 'exec 9>"$T/tree.lock"; flock 9; n=$(($(cat "$T/next") + 1)); echo $n >"$T/next"
jq --argjson id $n --arg app "$1" --argjson pid "$2" --arg ws "$3" --arg title "$4" \
  "(.nodes[0].nodes[] | select(.name == \$ws) | .nodes) += [{id: \$id, type: \"con\", app_id: \$app, name: \$title, pid: \$pid, nodes: []}]" \
  "$T/tree.json" >"$T/tree.new"; mv "$T/tree.new" "$T/tree.json"'
stub setsid '[[ $1 == -f ]] && shift; echo "$*" >>"$T/setsid.log"; exec "$@"'
stub foot 'app="" title=""; for a; do case $a in --app-id=*) app=${a#*=} ;; --title=*) title=${a#*=} ;; esac; done
case $app in ultron-review-*) ws=2:review ;; *) ws=4:watch ;; esac; addwin "$app" 900100 "$ws" "$title"'
stub chromium 'url=""; for a; do case $a in --app=*) url=${a#*=} ;; esac; done
[[ -s "$T/chromium.pid" ]] || echo 900200 >"$T/chromium.pid"; addwin chrome-app "$(cat "$T/chromium.pid")" 6:term "$url"'
stub pgrep 'case "$*" in *--user-data-dir=*) cat "$T/chromium.pid" 2>/dev/null ;; *) exit 1 ;; esac'
stub imv 'addwin imv $$ 6:term "$2"'
stub zeditor 'echo "$*" >>"$T/zed.log"'
stub notify-send ':'
echo '[{"name":"6:term","focused":true}]' >"$t/ws.json"
echo 100 >"$t/next"
jq -n '{id: 1, type: "root", nodes: [{id: 2, type: "output", nodes: [
  {id: 3, type: "workspace", name: "2:review", nodes: []}, {id: 4, type: "workspace", name: "3:web", nodes: []},
  {id: 5, type: "workspace", name: "4:watch", nodes: []},
  {id: 6, type: "workspace", name: "6:term", nodes: [{id: 20, type: "con", app_id: "foot", name: "mine", pid: 900001, nodes: []}]}]}]}' >"$t/tree.json"
touch "$t/sway.log" "$t/setsid.log" "$t/zed.log"
fail() {
  echo "FAIL show: $*"
  exit 1
}
want() { [[ $2 =~ $1 ]] || fail "want /$1/ in: $2"; }
logged() { grep -qxF -- "$2" "$t/$1.log" || fail "$1 didn't get: $2"; }
ultron() { bin/ultron "$@"; }

out=$(ULTRON_TAG=t1 ultron show review --cwd "$t/wt1" -- true)
want '^opened on workspace 2 \(id ultron-review-[0-9]+\)$' "$out"
review=$(jq -r '.. | objects | select((.app_id? // "") | startswith("ultron-review-")) | .id' "$t/tree.json")
[[ $(jq -r --argjson id "$review" '.. | objects | select(.id? == $id) | .name' "$t/tree.json") == "[t1] true" ]] ||
  fail "the tag isn't in the terminal's title"
want '^opened on workspace 4 ' "$(ultron show watch --cwd "$t/wt2" --tag t2 --title logs -- tail -f x)"
want '^opened on workspace 2 \(id web:[0-9]+\)$' "$(ultron show web 'http://127.0.0.1:47400/brief/thread-ab?t=1')"
web=$(<"$t/next")
logged sway "[con_id=$web] move container to workspace \"2:review\""
logged sway "[con_id=$web] layout tabbed"
grep -qF -- "--user-data-dir=$HOME/.local/share/ultron/chromium-preview --password-store=basic --no-first-run --app=http://127.0.0.1:47400/brief/thread-ab?t=1" \
  "$t/setsid.log" || fail "the preview browser's command line"
want '^opened on workspace 3 ' "$(ultron show web http://localhost:3000/)"
want '^opened on workspace 4 ' "$(ultron show web http://127.0.0.1:47400/board)"
want '^opened on workspace 4 ' "$(ultron show web http://localhost:3000/x --ws 4)"
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\x08\x06\0\0\0\x1f\x15\xc4\x89' >"$t/a.png"
want '^opened on workspace 2 \(id con:[0-9]+\)$' "$(ultron show file "$t/a.png" --tag t1)"
logged sway "[con_id=$(<"$t/next")] move container to workspace \"2:review\""
printf '<!doctype html><html><body>hi</body></html>\n' >"$t/a.html"
want '^opened on workspace 3 \(id web:' "$(ultron show file "$t/a.html")"
grep -qF -- "--app=file://$t/a.html" "$t/setsid.log" || fail "an HTML file didn't open as a web page"
want '^opened on workspace 5' "$(ultron show code "$t/a.html:12:3")"
logged zed "$t/a.html:12:3"
ultron show code "$t/nope.rs:1" 2>/dev/null && fail "show code opened a missing file"

# Nothing moved the user; the bar marks 2, 4, 3 and 5 (in that order); the newest window is remembered.
grep -qE '^workspace|focus$' "$t/sway.log" && fail "show moved the user"
grep -q jump "$t/setsid.log" && fail "show started a jump"
[[ $(paste -sd' ' "$R/new") == "2 4 3 5" ]] || fail "marks: $(paste -sd' ' "$R/new")"
[[ $(<"$R/shown-last") =~ ^[0-9]+$ ]] || fail "shown-last"
# A window shown on the workspace the user is on isn't marked.
: >"$R/new"
echo '[{"name":"2:review","focused":true}]' >"$t/ws.json"
ultron show review -- true >/dev/null
[[ ! -s "$R/new" ]] || fail "the focused workspace was marked"

list=$(ultron show list)
[[ $(wc -l <<<"$list") == 9 ]] || fail "list: $list"
want $'ultron-review-[0-9]+\t2:review\tt1\t\\[t1\\] true' "$list"
[[ $(grep -c $'\tt1\t' <<<"$list") == 2 ]] || fail "two windows carry tag t1: $list"
out=$(ultron show close --tag t1)
[[ $out == "closed 2 window(s) with tag t1" ]] || fail "close --tag: $out"
logged sway "[con_id=$review] kill"
ultron show close web:"$web" >/dev/null
logged sway "[con_id=$web] kill"
ultron show close 20 2>/dev/null && fail "show close accepted a window it didn't open"

# attentiond: a tagged window whose folder is gone closes when the user changes workspace; an agent's visible
# browser goes to 3, the preview browser stays where show put it.
watch=$(jq -r '.. | objects | select((.app_id? // "") | startswith("ultron-watch-")) | .id' "$t/tree.json")
rm -rf "$t/wt2"
printf '4\n' >"$R/new"
bash -c 'source lib/common.sh; source lib/cmd/attentiond.sh; _attn_event ws 4:watch'
logged sway "[con_id=$watch] kill"
grep -q "^$watch"$'\t' "$R/shown" && fail "the closed window stayed in the registry"
[[ ! -s "$R/new" ]] || fail "visiting 4 didn't clear its mark"
printf '#!/bin/bash\nsleep 30\n' >"$t/fakebrowser"
chmod +x "$t/fakebrowser"
"$t/fakebrowser" --remote-debugging-port=9222 &
fb=$!
for ((i = 0; i < 50; i++)); do
  if grep -q remote-debugging "/proc/$fb/cmdline" 2>/dev/null; then break; fi
  sleep 0.1
done
addwin chromium "$fb" 6:term agent
agent=$(<"$t/next")
bash -c 'source lib/common.sh; source lib/cmd/attentiond.sh; _attn_event new "$1" "$2"; _attn_event new 1 '$$ _ "$agent" "$fb"
logged sway "[con_id=$agent] move container to workspace \"3:web\""
grep -q $'\tagent-web:'"$agent"$'\t' "$R/shown" || fail "the agent's browser isn't in the registry"
grep -q 'con_id=1]' "$t/sway.log" && fail "attentiond moved a window that isn't an agent's browser"
echo "show ok"
