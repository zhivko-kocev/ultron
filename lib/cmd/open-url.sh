# shellcheck shell=bash
# ultron open-url URL: the default link handler. Localhost goes to the preview Chromium on
# workspace 3, everything else to the everyday browser.

cmd_open_url() {
  local url=${1:-}
  [[ -n "$url" ]] || die "usage: ultron open-url URL"
  # A file path (from a file manager) becomes a file:// URL; anything else must look like a URL.
  if [[ "$url" == /* ]]; then
    url="file://$url"
  elif [[ ! "$url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
    die "not a URL: $url"
  fi
  if [[ "$(_url_host "$url")" =~ ^(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0|.+\.localhost)$ ]]; then
    # shellcheck source=show.sh
    source "$ULTRON_ROOT/lib/cmd/show.sh"
    cmd_show web "$url"
  else
    # shellcheck source=browser.sh
    source "$ULTRON_ROOT/lib/cmd/browser.sh"
    cmd_browser "$url"
  fi
}
