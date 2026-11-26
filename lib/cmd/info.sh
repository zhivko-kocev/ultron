# shellcheck shell=bash
# ultron info [--json]: facts about this machine for agents and people. Fast: no sudo, no network.

# Purpose of each workspace (index = number); 2, 3 and 4 are the ones agents may open windows on.
_INFO_WS_PURPOSE=("" "the boss agent's window" "reviews, diffs, files and test runs opened by agents"
  "local web pages opened by agents" "live terminals opened by agents" "code editor" "your terminals"
  "chat apps" "free" "free" "system monitor and updates")

cmd_info() {
  local json=0
  case ${1:-} in
  --json) json=1 ;;
  "") ;;
  *) die "usage: ultron info [--json]" ;;
  esac

  local version host boss browser theme local_ai model docker_host away=false focus=false
  version=$(git -C "$ULTRON_ROOT" describe --tags --always 2>/dev/null || echo unknown)
  host=${HOSTNAME:-$(uname -n)}
  conf_var boss BOSS
  conf_var browser BROWSER
  conf_var theme THEME
  conf_var local_ai LOCAL_AI
  conf_var model ASK_MODEL
  docker_host=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}
  if is_away; then away=true; fi
  if [[ -e "$R/focus" ]]; then focus=true; fi
  local ai_on=false
  if [[ "$local_ai" == yes ]]; then ai_on=true; fi

  local n ws_tsv=""
  for ((n = 1; n <= 10; n++)); do
    local agents=no
    if ((n >= 2 && n <= 4)); then agents=yes; fi
    ws_tsv+="$n"$'\t'"${WS[$n]}"$'\t'"${_INFO_WS_PURPOSE[$n]}"$'\t'"$agents"$'\n'
  done

  if ((json)); then
    local ws_json
    ws_json=$(printf '%s' "$ws_tsv" | jq -R -s '
      split("\n") | map(select(length > 0) | split("\t")
        | {number: (.[0] | tonumber), name: .[1], purpose: .[2], agents: (.[3] == "yes")})')
    jq -n \
      --arg version "$version" --arg user "$ULTRON_USER" --arg host "$host" \
      --arg boss "$boss" --arg browser "$browser" --arg theme "$theme" \
      --argjson workspaces "$ws_json" \
      --argjson ai_on "$ai_on" --arg model "$model" \
      --arg docker_host "$docker_host" \
      --arg conf "$ULTRON_CONF" --arg conf_dir "$ULTRON_CONF_DIR" --arg generated "$ULTRON_GEN" \
      --arg agents_tsv "$ULTRON_CONF_DIR/agents.tsv" \
      --argjson away "$away" --argjson focus "$focus" \
      '{
        ultron: $version, user: $user, host: $host,
        boss: $boss, browser: $browser, theme: $theme,
        workspaces: $workspaces,
        local_ai: {enabled: $ai_on, model: $model, endpoint: "http://127.0.0.1:11434"},
        docker: {rootless: true, host: $docker_host},
        settings: {file: $conf, overrides: $conf_dir, generated: $generated, agents: $agents_tsv},
        user_state: {away: $away, focus_mode: $focus}
      }'
    return 0
  fi

  local name purpose agents
  cat <<EOF
ultron     $version
user       $ULTRON_USER@$host
boss       $boss
browser    $browser
theme      $theme

workspaces (agents open windows only on those marked *)
EOF
  while IFS=$'\t' read -r n name purpose agents; do
    local mark=" "
    if [[ "$agents" == yes ]]; then mark="*"; fi
    printf '  %s %-3s %-10s %s\n' "$mark" "$n" "$name" "$purpose"
  done <<<"${ws_tsv%$'\n'}"
  cat <<EOF

local AI   $(if [[ "$ai_on" == true ]]; then echo "on, model $model at http://127.0.0.1:11434 (ask \"...\")"; else echo off; fi)
docker     rootless, DOCKER_HOST=$docker_host
settings   $ULTRON_CONF (ultron conf), overrides in $ULTRON_CONF_DIR/
agents     extra agents in $ULTRON_CONF_DIR/agents.tsv
user now   $(if [[ "$away" == true ]]; then echo away; else echo "at the desk"; fi)$(if [[ "$focus" == true ]]; then echo ", focus mode on"; fi)
EOF
}
