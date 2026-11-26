# shellcheck shell=bash
# ultron browser [URL...]: the everyday browser (the BROWSER setting).

cmd_browser() {
  local cmd=()
  read -ra cmd <<<"$(browser_cmd)"
  have "${cmd[0]}" || die "browser '${cmd[0]}' isn't installed (ultron conf set BROWSER <command>)"
  detach "${cmd[@]}" "$@"
}
