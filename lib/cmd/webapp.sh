# shellcheck shell=bash
# ultron webapp add NAME URL [--ws N] | remove NAME | list | open SLUG
# A web app is a launcher (in the app list, Super+Space) that opens a site in its own browser
# window. --ws N also sends that window to workspace N.

_WEBAPP_APPS="$HOME/.local/share/applications"
_WEBAPP_SWAY="$ULTRON_CONF_DIR/sway"

# _webapp_slug NAME: lowercase, every run of other characters becomes one dash.
_webapp_slug() {
  local s
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  [[ -n "$s" ]] || die "'$1' has no letters or digits to name the web app by"
  printf '%s\n' "$s"
}

_webapp_desktop() { printf '%s\n' "$_WEBAPP_APPS/ultron-webapp-$1.desktop"; }
_webapp_rule() { printf '%s\n' "$_WEBAPP_SWAY/webapp-$1.conf"; }

_webapp_reload() {
  if in_sway; then swaymsg reload >/dev/null; fi
}

_webapp_add() {
  local name=${1:-} url=${2:-} ws="" slug file rule host had_rule=0
  [[ -n "$name" && -n "$url" ]] || die "usage: ultron webapp add NAME URL [--ws N]"
  shift 2
  while (($#)); do
    case $1 in
    --ws)
      ws=${2:-}
      [[ -n "$ws" ]] || die "--ws needs a workspace number (1-10)"
      shift
      ;;
    *) die "unknown option '$1' (usage: ultron webapp add NAME URL [--ws N])" ;;
    esac
    shift
  done
  [[ "$name" != *$'\n'* ]] || die "the name must be one line"
  [[ "$url" =~ ^https?://[^/[:space:]]+[^[:space:]]*$ ]] || die "the address must start with http:// or https:// (got '$url')"
  if [[ -n "$ws" ]]; then ws_name "$ws" >/dev/null; fi
  slug=$(_webapp_slug "$name")
  file=$(_webapp_desktop "$slug")
  rule=$(_webapp_rule "$slug")
  host=$(_url_host "$url")

  mkdir -p "$_WEBAPP_APPS"
  cat >"$file" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$url
Exec=ultron webapp open $slug
X-Ultron-URL=$url
Terminal=false
Categories=Network;
EOF
  ok "Added '$name': find it with Super+Space"

  if [[ -e "$rule" ]]; then had_rule=1; fi
  if [[ -n "$ws" ]]; then
    mkdir -p "$_WEBAPP_SWAY"
    # Chromium-based browsers name app windows chrome-HOST__PATH-PROFILE.
    printf '# Web app %s: its windows open on workspace %s.\nassign [app_id="^chrom(e|ium)-%s__"] workspace %s\n' \
      "$name" "$ws" "${host//./\\.}" "$(ws_name "$ws")" >"$rule"
    ok "Its windows open on workspace $ws"
    _webapp_reload
  elif ((had_rule)); then
    rm -f "$rule"
    _webapp_reload
  fi
}

_webapp_remove() {
  local slug file rule
  [[ -n "${1:-}" ]] || die "usage: ultron webapp remove NAME"
  slug=$(_webapp_slug "$1")
  file=$(_webapp_desktop "$slug")
  rule=$(_webapp_rule "$slug")
  [[ -e "$file" || -e "$rule" ]] || die "no web app called '$1' (see 'ultron webapp list')"
  rm -f "$file"
  if [[ -e "$rule" ]]; then
    rm -f "$rule"
    _webapp_reload
  fi
  ok "Removed web app '$1'"
}

_webapp_list() {
  local f slug name url
  for f in "$_WEBAPP_APPS"/ultron-webapp-*.desktop; do
    [[ -e "$f" ]] || continue
    slug=${f##*/ultron-webapp-}
    slug=${slug%.desktop}
    name=$(sed -n 's/^Name=//p' "$f" | head -n 1)
    url=$(sed -n 's/^X-Ultron-URL=//p' "$f" | head -n 1)
    printf '%s\t%s\t%s\n' "$slug" "$name" "$url"
  done
}

# _webapp_browser ARRAY: the command for app windows; --app needs a Chromium-based browser.
_webapp_browser() {
  local -n _wb_out=$1
  local words=()
  read -r -a words <<<"$(browser_cmd)"
  if ((${#words[@]})) && [[ "${words[0]##*/}" =~ chrom|brave|vivaldi|edge ]] && have "${words[0]}"; then
    _wb_out=("${words[@]}")
  else
    _wb_out=(chromium)
  fi
}

_webapp_open() {
  local slug=${1:-} file url browser=()
  [[ -n "$slug" ]] || die "usage: ultron webapp open SLUG"
  file=$(_webapp_desktop "$slug")
  if [[ ! -e "$file" ]]; then
    desktop_notify -u critical "Web app missing" "No web app '$slug' (see ultron webapp list)"
    die "no web app '$slug' (see 'ultron webapp list')"
  fi
  url=$(sed -n 's/^X-Ultron-URL=//p' "$file" | head -n 1)
  [[ -n "$url" ]] || die "$file has no X-Ultron-URL line"
  _webapp_browser browser
  if ! have "${browser[0]}"; then
    desktop_notify -u critical "No browser for web apps" "Web apps need Chromium, Chrome, Brave, Vivaldi or Edge: install one (Install in the menu)"
    die "web apps need a Chromium-based browser: run 'ultron pkg install chromium'"
  fi
  detach "${browser[@]}" --app="$url"
}

cmd_webapp() {
  local sub=${1:-list}
  if (($#)); then shift; fi
  case $sub in
  add) _webapp_add "$@" ;;
  remove) _webapp_remove "$@" ;;
  list) _webapp_list ;;
  open) _webapp_open "$@" ;;
  *) die "usage: ultron webapp add NAME URL [--ws N] | remove NAME | list | open SLUG" ;;
  esac
}
