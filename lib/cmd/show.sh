# shellcheck shell=bash
# ultron show review|web|watch: open something for the user on workspace 2 / 3 / 4.

cmd_show() {
  local kind=${1:-}
  shift || true
  case $kind in
  review) _show_term review 2 "$@" ;;
  watch) _show_term watch 4 "$@" ;;
  web) _show_web "$@" ;;
  *) die "usage: ultron show review [--cwd D] [--hold] [-- CMD...] | web URL | watch [--cwd D] [--title T] -- CMD..." ;;
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
  ((hold)) && args+=(--hold)
  [[ -n "$title" ]] && args+=(--title="$title")
  detach foot "${args[@]}" -- "${cmd[@]}"

  local id
  id=$(wait_window "^$app_id\$" 10) || die "the $kind window did not appear within 10 s"
  # The window is already on its workspace (sway assign); moving the user waits for the typing guard,
  # so it runs detached and the caller is not held up.
  detach "$ULTRON_ROOT/bin/ultron" jump "$n" --con-id "$id"
  echo "opened on workspace $n"
}

_show_web() {
  local url=${1:-}
  [[ -n "$url" ]] || die "usage: ultron show web URL"
  local filter='(.app_id // "") | test("^(ultron-web|chromium)$")'
  local before
  before=" $(sway_ids "$filter" | tr '\n' ' ') "

  mkdir -p "$PREVIEW_PROFILE"
  detach chromium --user-data-dir="$PREVIEW_PROFILE" --class=ultron-web --no-first-run --new-window "$url"

  local i id="" cand app
  for ((i = 0; i < 200; i++)); do
    while IFS= read -r cand; do
      [[ -n "$cand" && "$before" != *" $cand "* ]] && id=$cand
    done < <(sway_ids "$filter")
    [[ -n "$id" ]] && break
    sleep 0.1
  done
  [[ -n "$id" ]] || die "the preview window did not appear within 20 s"

  app=$(swaymsg -t get_tree | jq -r --argjson id "$id" '.. | objects | select(.id == $id) | .app_id // ""')
  if [[ "$app" != ultron-web ]]; then
    swaymsg "[con_id=$id] move container to workspace \"${WS[3]}\"" >/dev/null
  fi
  detach "$ULTRON_ROOT/bin/ultron" jump 3 --con-id "$id"
  echo "opened on workspace 3"
}
