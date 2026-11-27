#!/usr/bin/env bash
# attention: requests queue per window, oldest first, and a repeat keeps its place; focus mode marks instead of
# jumping; Super+A walks the queue, then the newest shown window; jump moves only for a request; attentiond
# drops what the user reached. sway is a stub that serves a canned tree and logs commands.
# shellcheck disable=SC2016 # stub bodies are scripts of their own: their $ must reach the file unexpanded.
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export T=$t HOME=$t/home XDG_RUNTIME_DIR=$t/run ULTRON_ROOT=$PWD PATH="$t/bin:$PATH"
unset SWAYSOCK ULTRON_TAG JOCASTA_THREAD
R=$XDG_RUNTIME_DIR/ultron
mkdir -p "$t/bin" "$HOME" "$R"
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$t/bin/$1"
  chmod +x "$t/bin/$1"
}
stub swaymsg 'if [[ $1 == -t ]]; then case $2 in get_tree) cat "$T/tree.json" ;; get_workspaces) cat "$T/ws.json" ;; esac; else echo "$*" >>"$T/sway.log"; fi'
stub notify-send 'echo "$*" >>"$T/notify.log"; if [[ " $* " == *" -p "* ]]; then echo 7; fi'
stub setsid 'echo "$*" >>"$T/setsid.log"'
stub pgrep 'exit 1'
stub makoctl 'echo "$*" >>"$T/mako.log"'
echo '[{"name":"5:code","focused":true}]' >"$t/ws.json"
touch "$t/sway.log" "$t/notify.log" "$t/setsid.log" "$t/mako.log"

# mktree FOCUSED_CON: windows 10 (boss, 1:boss), 40 (2:review), 20 (6:term), 21 (7:chat).
mktree() {
  jq -n --argjson f "$1" '
    def win(id; app; pid): {id: id, type: "con", app_id: app, name: app, focused: (id == $f), pid: pid, nodes: []};
    {id: 1, type: "root", nodes: [{id: 2, type: "output", nodes: [
      {id: 3, type: "workspace", name: "1:boss", nodes: [win(10; "ultron-boss"; 900001)]},
      {id: 4, type: "workspace", name: "2:review", nodes: [win(40; "imv"; 900002)]},
      {id: 5, type: "workspace", name: "6:term", nodes: [win(20; "foot"; 900003)]},
      {id: 6, type: "workspace", name: "7:chat", nodes: [win(21; "foot"; 900004)]}]}]}' >"$t/tree.json"
}
fail() {
  echo "FAIL attention: $*"
  exit 1
}
logged() { grep -qxF -- "$2" "$t/$1.log" || fail "$1 didn't get: $2"; }
ultron() { bin/ultron "$@"; }
# raise CON TITLE: `attention --raise TITLE` from an agent in window CON (the CLI finds CON from its process tree).
raise() { bash -c 'source lib/common.sh; source lib/cmd/attention.sh; attention_raise "$2" "$1"' _ "$1" "$2"; }

# Focus mode: queued and marked, nobody moved.
touch "$R/focus"
mktree 0
raise 20 one
[[ -f "$R/attention/20" ]] || fail "no request for window 20"
logged sway '[con_id=20] urgent enable'
sleep 1
raise 21 two
sleep 1
raise 20 'one again'
[[ $(sed -n 2p "$R/attention/20") == "one again" ]] || fail "a repeat didn't replace the title"
grep -q jump "$t/setsid.log" && fail "focus mode started a jump"
list=$(ultron attention --list | cut -f2,3)
[[ $list == $'6:term\tone again\n7:chat\ttwo' ]] || fail "list, oldest first: got $list"
ultron info --json | jq -e '(.attention | map(.title)) == ["one again", "two"]' >/dev/null || fail "info --json attention"

# Out of focus mode a request starts a jump; a request from the focused window is already answered.
rm "$R/focus"
raise 21 'two again'
grep -q 'ultron jump$' "$t/setsid.log" || fail "no jump started"
mktree 40
raise 40 seen
[[ ! -e "$R/attention/40" ]] || fail "the focused window's request stayed"
# The CLI: an agent outside any window is the boss's request. Its notification is replaced by a repeat and
# dismissed with the request.
mktree 0
ultron attention --raise boss
[[ $(sed -n 3p "$R/attention/10") == 1:boss ]] || fail "a raise from outside a window didn't fall back to the boss"
[[ $(sed -n 4p "$R/attention/10") == 7 ]] || fail "the request didn't keep its notification's id"
ultron attention --raise 'boss again'
logged notify '-a ultron -p -r 7 An agent needs you boss again'
bash -c 'source lib/common.sh; source lib/cmd/attention.sh; attention_seen 10'
[[ ! -e "$R/attention/10" ]] || fail "the seen request stayed"
logged mako 'dismiss -n 7'

# Super+A walks the queue, then goes to the newest shown window, then says nothing needs you.
ultron attention
logged sway 'workspace "6:term"'
logged sway '[con_id=20] focus'
[[ ! -e "$R/attention/20" ]] || fail "the visited request stayed"
ultron attention
logged sway '[con_id=21] focus'
echo 40 >"$R/shown-last"
echo 2 >"$R/new"
ultron attention
logged sway 'workspace "2:review"'
logged sway '[con_id=40] focus'
# The newest shown window was seen already (its workspace isn't marked): the newest shown window on a marked
# workspace, else the first marked workspace.
printf '40\tcon:40\t-\t-\n21\tcon:21\t-\t-\n' >"$R/shown"
echo 21 >"$R/shown-last"
printf '2\n' >"$R/new"
: >"$t/sway.log"
ultron attention
logged sway 'workspace "2:review"'
logged sway '[con_id=40] focus'
printf '4\n' >"$R/new"
ultron attention
logged sway 'workspace "4:watch"'
: >"$R/new"
ultron attention
logged notify '-a ultron Nothing needs you '

# jump: nothing waiting -> no move; focus mode -> the mark; else the oldest, after the typing guard.
touch "$R/idle2"
: >"$t/sway.log"
ultron jump
[[ ! -s "$t/sway.log" ]] || fail "a jump with nothing waiting moved the user"
touch "$R/focus"
raise 21 three
: >"$t/sway.log"
ultron jump
logged sway '[con_id=21] urgent enable'
grep -q focus "$t/sway.log" && fail "a jump in focus mode moved the user"
rm "$R/focus"
ultron jump &
for ((i = 0; i < 50; i++)); do
  if grep -qxF '[con_id=21] focus' "$t/sway.log"; then break; fi
  sleep 0.1
done
logged sway '[con_id=21] focus'
rm "$R/idle2"
wait $!
ultron jump 2 2>/dev/null && fail "jump took an argument"

# attentiond: a focused window answers its request; reaching a workspace clears its mark and drops requests
# of windows that are gone.
mkdir -p "$R/attention"
printf '%s\nold\n9\n' "$(date -Iseconds)" >"$R/attention/99"
printf '%s\nx\n7:chat\n' "$(date -Iseconds)" >"$R/attention/21"
printf '2\n3\n' >"$R/new"
bash -c 'source lib/common.sh; source lib/cmd/attentiond.sh; _attn_event focus 21; _attn_event ws 2:review'
[[ ! -e "$R/attention/21" ]] || fail "attentiond kept the focused window's request"
[[ ! -e "$R/attention/99" ]] || fail "attentiond kept a closed window's request"
[[ $(<"$R/new") == 3 ]] || fail "attentiond didn't clear workspace 2's mark"
echo "attention ok"
