# shellcheck shell=bash
# ultron open-url URL: the default browser. Localhost goes to the preview Chromium, the rest to Chrome.

cmd_open_url() {
  local url=${1:-}
  [[ -n "$url" ]] || die "usage: ultron open-url URL"
  if [[ "$(_url_host "$url")" =~ ^(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0|.+\.localhost)$ ]]; then
    source "$ULTRON_ROOT/lib/cmd/show.sh"
    _show_web "$url"
  else
    detach google-chrome-stable "$url"
  fi
}

# _url_host URL: lowercased host of an http(s) URL ("[::1]" keeps its brackets); empty otherwise.
_url_host() {
  local url=$1 auth host
  [[ "$url" =~ ^[hH][tT][tT][pP][sS]?://([^/?#]*) ]] || return 0
  auth=${BASH_REMATCH[1]}
  auth=${auth##*@}
  if [[ "$auth" == \[* ]]; then
    host="${auth%%]*}]"
  else
    host=${auth%%:*}
  fi
  printf '%s\n' "${host,,}"
}
