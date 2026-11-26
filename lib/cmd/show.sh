# shellcheck shell=bash
# ultron show: open something for the user on workspace 2 / 3 / 4, and manage those windows.
#   show review [--cwd D] [--hold] [-- CMD...]   terminal on 2 (default: hunk diff --watch)
#   show web URL                                  preview Chromium on 3
#   show watch [--cwd D] [--title T] -- CMD...    terminal on 4 that stays open
#   show file PATH                                image, PDF, video, audio or text on 2
#   show list                                     ID, workspace and title of each window opened here
#   show close ID                                 close one of those windows (never anything else)

# Windows whose app_id can't be chosen (viewers, a Chromium that ignored --class) are recorded here
# as "CON_ID<TAB>ID", so list/close can tell them from the user's own windows.
_SHOW_OWNED="$R/shown"

cmd_show() {
  local kind=${1:-}
  shift || true
  case $kind in
  review) _show_term review 2 "$@" ;;
  watch) _show_term watch 4 "$@" ;;
  web) _show_web "$@" ;;
  file) _show_file "$@" ;;
  list) _show_list ;;
  close) _show_close "$@" ;;
  *) die "usage: ultron show review [--cwd D] [--hold] [-- CMD...] | web URL | watch [--cwd D] [--title T] -- CMD... | file PATH | list | close ID" ;;
  esac
}

# _show_term KIND N [--cwd D] [--hold] [--title T] [-- CMD...]
_show_term() {
  local kind=$1 n=$2
  shift 2
  local cwd=$PWD hold=0 title="" cmd=()
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
    --)
      shift
      cmd=("$@")
      break
      ;;
    *) die "show $kind: unknown option '$1' (put the command after --)" ;;
    esac
  done
  [[ -d "$cwd" ]] || die "show $kind: no such folder: $cwd"
  if [[ $kind == watch ]]; then
    hold=1
    ((${#cmd[@]})) || die "show watch needs a command: ultron show watch -- CMD..."
  fi
  ((${#cmd[@]})) || cmd=(hunk diff --watch)

  local app_id
  app_id="ultron-$kind-$(date +%s%N)"
  local args=(--app-id="$app_id" --working-directory="$cwd")
  if ((hold)); then args+=(--hold); fi
  if [[ -n "$title" ]]; then args+=(--title="$title"); fi
  detach foot "${args[@]}" -- "${cmd[@]}"

  local id
  id=$(wait_window "^$app_id\$" 10) || die "the $kind window did not appear within 10 s"
  # The window is already on its workspace (sway assign); moving the user waits for the typing guard,
  # so it runs detached and the caller is not held up.
  detach "$ULTRON_ROOT/bin/ultron" jump "$n" --con-id "$id"
  echo "opened on workspace $n (id $app_id)"
}

_show_web() {
  local url=${1:-}
  [[ -n "$url" ]] || die "usage: ultron show web URL"
  local filter='(.app_id // "") | test("^(ultron-web|chromium)$")'
  local before id app
  before=$(sway_ids "$filter" | tr '\n' ' ')

  mkdir -p "$PREVIEW_PROFILE"
  # basic: the preview profile never touches the keyring the everyday browser uses.
  detach chromium --user-data-dir="$PREVIEW_PROFILE" --class=ultron-web --password-store=basic \
    --no-first-run --new-window "$url"

  id=$(wait_new_window "$before" "$filter" 20) || die "the preview window did not appear within 20 s"
  app=$(swaymsg -t get_tree | jq -r --argjson id "$id" '.. | objects | select(.id == $id) | .app_id // ""')
  if [[ "$app" != ultron-web ]]; then
    swaymsg "[con_id=$id] move container to workspace \"${WS[3]}\"" >/dev/null
    _show_own "$id" web
  fi
  detach "$ULTRON_ROOT/bin/ultron" jump 3 --con-id "$id"
  echo "opened on workspace 3 (id web)"
}

_show_file() {
  local path=${1:-}
  [[ -n "$path" ]] || die "usage: ultron show file PATH"
  [[ -f "$path" && -r "$path" ]] || die "show file: not a readable file: $path"
  path=$(realpath -- "$path")

  local mime app
  local viewer=()
  mime=$(file --mime-type -b -- "$path")
  case $mime in
  image/*) viewer=(imv) app=imv ;;
  application/pdf) viewer=(zathura) app=org.pwmt.zathura ;;
  video/* | audio/*) viewer=(mpv --force-window=yes) app=mpv ;;
  text/* | application/json)
    _show_term review 2 --cwd "$(dirname -- "$path")" -- less -R -- "$path"
    return 0
    ;;
  *) die "show file: can't show $mime. Supported: images, PDF, video, audio, text and JSON" ;;
  esac
  have "${viewer[0]}" || die "show file: ${viewer[0]} isn't installed (sudo pacman -S ${viewer[0]})"

  local filter before id
  filter="(.app_id // \"\") == \"$app\""
  before=$(sway_ids "$filter" | tr '\n' ' ')
  detach "${viewer[@]}" -- "$path"
  id=$(wait_new_window "$before" "$filter" 10) || die "the ${viewer[0]} window did not appear within 10 s"
  swaymsg "[con_id=$id] move container to workspace \"${WS[2]}\"" >/dev/null
  _show_own "$id" "con:$id"
  detach "$ULTRON_ROOT/bin/ultron" jump 2 --con-id "$id"
  echo "opened on workspace 2 (id con:$id)"
}

# _show_own CON_ID ID: remember a window opened here whose app_id doesn't say so.
_show_own() {
  ensure_rundir
  printf '%s\t%s\n' "$1" "$2" >>"$_SHOW_OWNED"
}

# _show_rows: "ID<TAB>CON_ID<TAB>WORKSPACE<TAB>TITLE" for every window that show opened and that still exists.
# Also rewrites the record without windows that are gone.
_show_rows() {
  local -A owned=()
  local con oid app ws title
  if [[ -r "$_SHOW_OWNED" ]]; then
    while IFS=$'\t' read -r con oid; do
      if [[ "$con" =~ ^[0-9]+$ && -n "$oid" ]]; then owned[$con]=$oid; fi
    done <"$_SHOW_OWNED"
  fi
  local tree
  tree=$(swaymsg -t get_tree 2>/dev/null) || die "show: sway isn't running here"
  local -A alive=()
  # app_id "-" stands in for none (Xwayland), so the tab-separated fields never collapse.
  while IFS=$'\t' read -r con app ws title; do
    if [[ "$app" =~ ^ultron-(review|watch)-[0-9]+$ ]]; then
      oid=$app
    elif [[ "$app" == ultron-web ]]; then
      oid=web
    elif [[ -n "${owned[$con]-}" ]]; then
      oid=${owned[$con]}
      alive[$con]=$oid
    else
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$oid" "$con" "$ws" "$title"
  done < <(jq -r '
    .. | objects | select(.type == "workspace") | .name as $ws
    | .. | objects | select(has("app_id") or has("window_properties"))
    | [.id, (.app_id // "-"), $ws, ((.name // "") | gsub("[\t\n]"; " "))] | @tsv' <<<"$tree")
  if [[ -e "$_SHOW_OWNED" ]]; then
    local tmp
    tmp=$(mktemp "$R/.shown.XXXXXX")
    for con in "${!alive[@]}"; do printf '%s\t%s\n' "$con" "${alive[$con]}"; done >"$tmp"
    mv "$tmp" "$_SHOW_OWNED"
  fi
}

_show_list() {
  local rows oid con ws title
  rows=$(_show_rows)
  [[ -n "$rows" ]] || return 0
  while IFS=$'\t' read -r oid con ws title; do
    printf '%s\t%s\t%s\n' "$oid" "$ws" "$title"
  done <<<"$rows"
}

_show_close() {
  local want=${1:-}
  [[ -n "$want" ]] || die "usage: ultron show close ID (IDs come from: ultron show list)"
  if [[ ! "$want" =~ ^(ultron-(review|watch)-[0-9]+|web|con:[0-9]+)$ ]]; then
    die "show close: '$want' is not a window ultron show opened (IDs come from: ultron show list)"
  fi
  local rows oid con ws title pid n=0
  rows=$(_show_rows)
  while IFS=$'\t' read -r oid con ws title; do
    if [[ "$oid" == "$want" ]]; then
      swaymsg "[con_id=$con] kill" >/dev/null
      n=$((n + 1))
      if [[ "$want" == con:* ]]; then
        # Viewers (imv was seen doing this) can ignore the close request; each is its own process,
        # started here for this one file, so it is ended directly.
        sleep 0.3
        pid=$(swaymsg -t get_tree | jq -r --argjson id "$con" 'first(.. | objects | select(.id? == $id) | .pid) // empty')
        if [[ "$pid" =~ ^[0-9]+$ ]]; then kill "$pid" 2>/dev/null || true; fi
      fi
    fi
  done <<<"$rows"
  ((n)) || die "show close: no open window with id $want (see: ultron show list)"
  echo "closed $want"
}
