# shellcheck shell=bash
# ultron status: swaybar status line (i3bar JSON), one update every 2 s.

_blk() { # _blk NAME TEXT [COLOR]
  local text=${2//\\/\\\\}
  text=${text//\"/\\\"}
  if [[ -n "${3:-}" ]]; then
    printf '{"name":"%s","full_text":"%s","color":"%s"}' "$1" "$text" "$3"
  else
    printf '{"name":"%s","full_text":"%s"}' "$1" "$text"
  fi
}

_status_ai() {
  local ps
  ps=$(curl -fsS --max-time 1 http://127.0.0.1:11434/api/ps 2>/dev/null) || {
    echo "AI off"
    return
  }
  jq -r '(.models // []) | if length > 0 then "AI " + .[0].name else "AI idle" end' <<<"$ps" 2>/dev/null || echo "AI off"
}

_status_ts() {
  have tailscale || return 0
  if [[ $(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""' 2>/dev/null) == Running ]]; then
    echo "TS"
  else
    echo "TS off"
  fi
}

_status_vol() {
  local out pct
  out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 0
  [[ "$out" == *MUTED* ]] && {
    echo "VOL muted"
    return
  }
  pct=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$out")
  echo "VOL $pct%"
}

cmd_status() {
  local grey="#928374" red="#fb4934" yellow="#fabd2f" green="#b8bb26"
  local tick=0 ai="" ts="" first=1 kind
  local prev_total=0 prev_idle=0 total idle cpu=0 user nice sys idl iow irq sirq steal rest
  local mem_total mem_avail key val _unit

  printf '{"version":1}\n[\n'
  while :; do
    kind=$(boss_kind)
    ((tick % 5 == 0)) && ai=$(_status_ai)
    ((tick % 15 == 0)) && ts=$(_status_ts)

    read -r _ user nice sys idl iow irq sirq steal rest </proc/stat
    total=$((user + nice + sys + idl + iow + irq + sirq + steal))
    idle=$((idl + iow))
    if ((prev_total > 0 && total > prev_total)); then
      cpu=$(((100 * ((total - prev_total) - (idle - prev_idle))) / (total - prev_total)))
    fi
    prev_total=$total prev_idle=$idle

    mem_total=0 mem_avail=0
    while read -r key val _unit; do
      case $key in
      MemTotal:) mem_total=$val ;;
      MemAvailable:) mem_avail=$val ;;
      esac
    done </proc/meminfo

    local blocks=()
    if [[ $kind == jocasta ]]; then
      if ! jocasta_running; then
        blocks+=("$(_blk boss "J ✗" "$red")")
      elif [[ -e "$R/needs-you" ]]; then
        blocks+=("$(_blk boss "J ● needs you" "$red")")
      else
        blocks+=("$(_blk boss "J" "$grey")")
      fi
    else
      blocks+=("$(_blk boss "boss: $kind" "$grey")")
    fi
    [[ -e "$R/focus" ]] && blocks+=("$(_blk focus "FOCUS" "$yellow")")
    [[ -n "$ai" ]] && blocks+=("$(_blk ai "$ai" "$([[ $ai == "AI off" ]] && echo "$grey" || echo "")")")
    if [[ -n "$ts" ]]; then
      blocks+=("$(_blk ts "$ts" "$([[ $ts == TS ]] && echo "$green" || echo "$grey")")")
    fi
    blocks+=("$(_blk cpu "CPU $cpu%")")
    blocks+=("$(_blk ram "$(awk -v k=$((mem_total - mem_avail)) 'BEGIN{printf "RAM %.1fG", k / 1048576}')")")
    local vol
    vol=$(_status_vol)
    [[ -n "$vol" ]] && blocks+=("$(_blk vol "$vol")")
    blocks+=("$(_blk clock "$(date '+%a %d %b  %H:%M')")")

    local IFS=,
    if ((first)); then
      printf '[%s]\n' "${blocks[*]}"
      first=0
    else
      printf ',[%s]\n' "${blocks[*]}"
    fi
    unset IFS
    sleep 2
    tick=$((tick + 1))
  done
}
