# shellcheck shell=bash
# ultron notify [--phone] [--urgent] TITLE BODY: desktop notice; also a phone push with --phone or while away.

cmd_notify() {
  local phone=0 urgent=0
  while (($#)); do
    case $1 in
    --phone) phone=1 ;;
    --urgent) urgent=1 ;;
    --) shift; break ;;
    -*) die "notify: unknown option '$1'" ;;
    *) break ;;
    esac
    shift
  done
  local title=${1:-} body=${2:-}
  [[ -n "$title" ]] || die "usage: ultron notify [--phone] [--urgent] TITLE BODY"

  local args=(-a ultron)
  ((urgent)) && args+=(-u critical)
  notify-send "${args[@]}" "$title" "$body" 2>/dev/null || true

  if ((phone)) || is_away; then
    ntfy_load || return 0
    # JSON publishing keeps non-ASCII titles intact (HTTP headers are ASCII-only).
    local prio=3
    ((urgent)) && prio=4
    jq -n --arg t "$title" --arg m "${body:-$title}" --argjson p "$prio" \
      '{topic: "ultron-alerts", title: $t, message: $m, priority: $p}' |
      curl -fsS --max-time 10 -H "Authorization: Bearer $NTFY_TOKEN" --data-binary @- "$NTFY_URL" >/dev/null ||
      warn "phone push failed"
  fi
}
