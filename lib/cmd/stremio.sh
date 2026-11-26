# shellcheck shell=bash
# ultron stremio: the streaming server plus Stremio's web app in a Chrome app window.

cmd_stremio() {
  pgrep -x stremio-service >/dev/null 2>&1 || detach stremio-service
  detach google-chrome-stable --app=https://web.stremio.com/
}
