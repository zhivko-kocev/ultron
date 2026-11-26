# shellcheck shell=bash
# ultron show: open something for the user on workspace 2 / 3 / 4, and manage those windows.
# Showing never moves the user: the workspace is marked in the bar ("new 2") and Super+A goes there.
#   show review [--cwd D] [--hold] [--tag T] [-- CMD...]   terminal on 2 (default: hunk diff --watch)
#   show watch [--cwd D] [--title T] [--tag T] -- CMD...   terminal on 4 that stays open
#   show web URL [--ws 2|3|4] [--tag T]                      preview Chromium window (default 3; review pages 2, board 4)
#   show file PATH [--tag T]                                 image, PDF, video, audio or text on 2; HTML as web
#   show code FILE[:LINE[:COL]]                              the editor (Zed, workspace 5)
#   show list                                                ID, workspace, tag and title of each window opened here
#   show close ID | --tag T                                  close those windows (never anything else)
# --tag defaults to $ULTRON_TAG, else $JOCASTA_THREAD. A tagged window closes by itself once its folder is gone.
#
# State in $R, changed only under the lock $R/show.lock:
#   shown       registry, one line per window: CON_ID<TAB>ID<TAB>TAG<TAB>CWD ("-" = none)
#   new         workspace numbers holding shown windows the user hasn't looked at, one per line
#   shown-last  con id of the newest shown window

_SHOW_REG="$R/shown"

cmd_show() {
  local kind=${1:-}
  shift || true
  ensure_rundir
  exec 8>"$R/show.lock"
  flock 8
  case $kind in
  review) _show_term review 2 "$@" ;;
  watch) _show_term watch 4 "$@" ;;
  web) _show_web "$@" ;;
  file) _show_file "$@" ;;
  code) _show_code "$@" ;;
  list) _show_list ;;
  close) _show_close "$@" ;;
  *) die "usage: ultron show review [--cwd D] [--hold] [--tag T] [-- CMD...] | watch [--cwd D] [--title T] [--tag T] -- CMD... | web URL [--ws 2|3|4] [--tag T] | file PATH [--tag T] | code FILE[:LINE[:COL]] | list | close ID|--tag T" ;;
  esac
}

# show_locked CMD...: run CMD holding the show lock (for attentiond); skipped when it isn't free within 30 s.
show_locked() { { flock -w 30 7 || return 0; "$@"; } 7>"$R/show.lock"; }

# _show_tag VALUE: a tag usable in the registry (no whitespace; "-" means none).
_show_tag() {
  local tag=${1//[[:space:]]/_}
  if [[ "$tag" == - ]]; then tag=""; fi
  printf '%s\n' "$tag"
}

# show_reg_add CON_ID ID TAG CWD
show_reg_add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:--}" "${4:--}" >>"$_SHOW_REG"; }

# show_mark N [CON_ID]: workspace N got a window the user hasn't seen (unless they are on it).
show_mark() {
  local n=$1 cur
  cur=$(focused_ws 2>/dev/null || true)
  if [[ "${cur%%:*}" != "$n" ]] && ! grep -qx -- "$n" "$R/new" 2>/dev/null; then
    printf '%s\n' "$n" >>"$R/new"
  fi
  if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" >"$R/shown-last"; fi
}

# show_unmark N: the user is on workspace N.
show_unmark() {
  [[ -s "$R/new" ]] || return 0
  local tmp
  tmp=$(mktemp "$R/.new.XXXXXX")
  grep -vx -- "$1" "$R/new" >"$tmp" || true
  mv "$tmp" "$R/new"
}

# show_sweep ALIVE: drop registry lines of closed windows; close tagged windows whose folder is gone.
# ALIVE: " id id ... " (every window sway has).
show_sweep() {
  local alive=$1 con oid tag cwd tmp
  [[ -s "$_SHOW_REG" ]] || return 0
  tmp=$(mktemp "$R/.shown.XXXXXX")
  while IFS=$'\t' read -r con oid tag cwd; do
    [[ "$alive" == *" $con "* ]] || continue
    if [[ "$tag" != - && "$cwd" != - && ! -d "$cwd" ]]; then
      swaymsg "[con_id=$con] kill" >/dev/null 2>&1 || true
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$con" "$oid" "$tag" "$cwd"
  done <"$_SHOW_REG" >"$tmp"
  mv "$tmp" "$_SHOW_REG"
}

# _show_placed N CON_ID ID TAG CWD: record a window that is now on workspace N.
_show_placed() {
  show_reg_add "$2" "$3" "$4" "$5"
  show_mark "$1" "$2"
  echo "opened on workspace $1 (id $3)"
}

# _show_move CON_ID N: put a window on workspace N, as a tab.
_show_move() {
  swaymsg "[con_id=$1] move container to workspace \"${WS[$2]}\"" >/dev/null
  # Floating windows (imv) have no layout; sway refuses, and that's fine.
  swaymsg "[con_id=$1] layout tabbed" >/dev/null 2>&1 || true
}

# _show_wait_pid PID [TIMEOUT_S]: con_id of the newest window of process PID; 1 on timeout.
_show_wait_pid() {
  local pid=$1 limit=${2:-10} i id
  for ((i = 0; i < limit * 10; i++)); do
    id=$(sway_ids ".pid == $pid" | tail -n1)
    if [[ -n "$id" ]]; then
      printf '%s\n' "$id"
      return 0
    fi
    nap 0.1
  done
  return 1
}

# _show_term KIND N [--cwd D] [--hold] [--title T] [--tag T] [-- CMD...]
_show_term() {
  local kind=$1 n=$2
  shift 2
  local cwd=$PWD hold=0 title="" tag=${ULTRON_TAG:-${JOCASTA_THREAD:-}} cmd=()
  while (($#)); do
    case $1 in
    --cwd)
      cwd=${2:?--cwd needs a folder}
      shift 2
      ;;
    --hold)
      hold=1
      shift
      ;;
    --title)
      title=${2:?--title needs a value}
      shift 2
      ;;
    --tag)
      tag=${2?--tag needs a value}
      shift 2
      ;;
    --)
      shift
      cmd=("$@")
      break
      ;;
    *) die "show $kind: unknown option '$1' (put the command after --)" ;;
    esac
  done
  [[ -d "$cwd" ]] || die "show $kind: no such folder: $cwd"
  cwd=$(realpath -- "$cwd")
  tag=$(_show_tag "$tag")
  if [[ $kind == watch ]]; then
    hold=1
    ((${#cmd[@]})) || die "show watch needs a command: ultron show watch -- CMD..."
  fi
  ((${#cmd[@]})) || cmd=(hunk diff --watch)
  if [[ -n "$tag" ]]; then title="[$tag] ${title:-${cmd[*]}}"; fi

  local app_id
  app_id="ultron-$kind-$(date +%s%N)"
  local args=(--app-id="$app_id" --working-directory="$cwd")
  if ((hold)); then args+=(--hold); fi
  if [[ -n "$title" ]]; then args+=(--title="$title"); fi
  detach foot "${args[@]}" -- "${cmd[@]}" 8>&-

  local id
  id=$(wait_window "^$app_id\$" 10) || die "the $kind window did not appear within 10 s"
  # sway's assign rule put it on its workspace.
  _show_placed "$n" "$id" "$app_id" "$tag" "$cwd"
}

# _url_path URL: the path of a URL ("/" when it has none).
_url_path() {
  local p=${1#*://}
  if [[ "$p" == */* ]]; then p="/${p#*/}"; else p=/; fi
  printf '%s\n' "$p"
}

_show_web() {
  local url="" n="" tag=${ULTRON_TAG:-${JOCASTA_THREAD:-}}
  while (($#)); do
    case $1 in
    --ws)
      n=${2:-}
      [[ "$n" =~ ^[234]$ ]] || die "show web: --ws must be 2, 3 or 4"
      shift 2
      ;;
    --tag)
      tag=${2?--tag needs a value}
      shift 2
      ;;
    -*) die "show web: unknown option '$1'" ;;
    *)
      [[ -z "$url" ]] || die "usage: ultron show web URL [--ws 2|3|4] [--tag T]"
      url=$1
      shift
      ;;
    esac
  done
  [[ -n "$url" ]] || die "usage: ultron show web URL [--ws 2|3|4] [--tag T]"
  tag=$(_show_tag "$tag")
  if [[ -z "$n" ]]; then
    case $(_url_path "$url") in
    /brief/thread-* | /brief/pr-*) n=2 ;;
    /board | /board[/?#]*) n=4 ;;
    *) n=3 ;;
    esac
  fi

  local before id="" pid cand i
  before=" $(sway_ids true | tr '\n' ' ') "
  mkdir -p "$PREVIEW_PROFILE"
  # basic: the preview profile never touches the keyring the everyday browser uses.
  detach chromium --user-data-dir="$PREVIEW_PROFILE" --password-store=basic --no-first-run --app="$url" 8>&-
  # A running preview browser opens the window itself; either way it belongs to the profile's first process.
  for ((i = 0; i < 200; i++)); do
    pid=$(pgrep -o -f -- "--user-data-dir=$PREVIEW_PROFILE" || true)
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      while IFS= read -r cand; do
        if [[ -n "$cand" && "$before" != *" $cand "* ]]; then id=$cand; fi
      done < <(sway_ids ".pid == $pid")
    fi
    if [[ -n "$id" ]]; then break; fi
    nap 0.1
  done
  [[ -n "$id" ]] || die "the preview window did not appear within 20 s"
  _show_move "$id" "$n"
  _show_placed "$n" "$id" "web:$id" "$tag" "$PWD"
}

_show_file() {
  local path="" tag=${ULTRON_TAG:-${JOCASTA_THREAD:-}}
  while (($#)); do
    case $1 in
    --tag)
      tag=${2?--tag needs a value}
      shift 2
      ;;
    *)
      [[ -z "$path" ]] || die "usage: ultron show file PATH [--tag T]"
      path=$1
      shift
      ;;
    esac
  done
  [[ -n "$path" ]] || die "usage: ultron show file PATH [--tag T]"
  [[ -f "$path" && -r "$path" ]] || die "show file: not a readable file: $path"
  path=$(realpath -- "$path")

  local mime viewer=()
  mime=$(file --mime-type -b -- "$path")
  case $mime in
  text/html)
    _show_web "file://$path" --tag "$tag"
    return 0
    ;;
  image/*) viewer=(imv) ;;
  application/pdf) viewer=(zathura) ;;
  video/* | audio/*) viewer=(mpv --force-window=yes) ;;
  text/* | application/json)
    _show_term review 2 --cwd "$(dirname -- "$path")" --tag "$tag" -- less -R -- "$path"
    return 0
    ;;
  *) die "show file: can't show $mime. Supported: images, PDF, video, audio, text, JSON and HTML" ;;
  esac
  have "${viewer[0]}" || die "show file: ${viewer[0]} isn't installed (sudo pacman -S ${viewer[0]})"
  tag=$(_show_tag "$tag")

  local pid id
  setsid "${viewer[@]}" -- "$path" </dev/null >/dev/null 2>&1 8>&- &
  pid=$!
  disown
  id=$(_show_wait_pid "$pid" 10) || die "the ${viewer[0]} window did not appear within 10 s"
  _show_move "$id" 2
  _show_placed 2 "$id" "con:$id" "$tag" "$PWD"
}

_show_code() {
  local arg=${1:-} f
  [[ -n "$arg" ]] || die "usage: ultron show code FILE[:LINE[:COL]]"
  f=$arg
  while [[ ! -e "$f" && "$f" =~ ^(.+):[0-9]+$ ]]; do f=${BASH_REMATCH[1]}; done
  [[ -f "$f" ]] || die "show code: no such file: $f"
  have zeditor || die "show code: Zed isn't installed (sudo pacman -S zed)"
  detach zeditor "$(realpath -- "$f")${arg#"$f"}" 8>&-
  # sway's assign rule puts Zed on workspace 5.
  show_mark 5
  echo "opened on workspace 5 (in Zed)"
}

# _show_rows: "ID<TAB>CON_ID<TAB>WORKSPACE<TAB>TAG<TAB>TITLE" for every window show opened that still exists
# ("-" for no tag). Also drops registry lines of windows that are gone.
_show_rows() {
  local tree con ws title oid tag cwd
  tree=$(swaymsg -t get_tree 2>/dev/null) || die "show: sway isn't running here"
  local -A where=() name=()
  while IFS=$'\t' read -r con ws title; do
    where[$con]=$ws name[$con]=$title
  done < <(jq -r '
    .. | objects | select(.type? == "workspace") | .name as $ws
    | .. | objects | select(has("app_id") or has("window_properties"))
    | [.id, $ws, ((.name // "") | gsub("[\t\n]"; " "))] | @tsv' <<<"$tree")
  [[ -s "$_SHOW_REG" ]] || return 0
  local tmp
  tmp=$(mktemp "$R/.shown.XXXXXX")
  while IFS=$'\t' read -r con oid tag cwd; do
    [[ -n "${where[$con]-}" ]] || continue
    printf '%s\t%s\t%s\t%s\n' "$con" "$oid" "$tag" "$cwd" >>"$tmp"
    printf '%s\t%s\t%s\t%s\t%s\n' "$oid" "$con" "${where[$con]}" "$tag" "${name[$con]}"
  done <"$_SHOW_REG"
  mv "$tmp" "$_SHOW_REG"
}

_show_list() {
  local rows oid con ws tag title
  rows=$(_show_rows)
  [[ -n "$rows" ]] || return 0
  while IFS=$'\t' read -r oid con ws tag title; do
    if [[ "$tag" == - ]]; then tag=""; fi
    printf '%s\t%s\t%s\t%s\n' "$oid" "$ws" "$tag" "$title"
  done <<<"$rows"
}

_show_close() {
  local want=${1:-} by=id
  if [[ "$want" == --tag ]]; then
    by=tag
    want=$(_show_tag "${2:-}")
    [[ -n "$want" ]] || die "usage: ultron show close --tag T"
  elif [[ ! "$want" =~ ^(ultron-(review|watch)-[0-9]+|(web|con|agent-web):[0-9]+)$ ]]; then
    die "usage: ultron show close ID | --tag T (IDs come from: ultron show list)"
  fi
  local rows oid con ws tag title pid n=0
  rows=$(_show_rows)
  while IFS=$'\t' read -r oid con ws tag title; do
    if [[ $by == id && "$oid" != "$want" ]] || [[ $by == tag && "$tag" != "$want" ]]; then continue; fi
    swaymsg "[con_id=$con] kill" >/dev/null
    n=$((n + 1))
    if [[ "$oid" == con:* ]]; then
      # Viewers (imv was seen doing this) can ignore the close request; each is its own process,
      # started here for this one file, so it is ended directly.
      sleep 0.3
      pid=$(swaymsg -t get_tree | jq -r --argjson id "$con" 'first(.. | objects | select(.id? == $id) | .pid) // empty')
      if [[ "$pid" =~ ^[0-9]+$ ]]; then kill "$pid" 2>/dev/null || true; fi
    fi
  done <<<"$rows"
  ((n)) || die "show close: no open window with $by $want (see: ultron show list)"
  if [[ $by == id ]]; then echo "closed $want"; else echo "closed $n window(s) with tag $want"; fi
}
