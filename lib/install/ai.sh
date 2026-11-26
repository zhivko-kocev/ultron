# shellcheck shell=bash
# step ai: ollama (Vulkan) with the ASK_MODEL model, when local AI is on (local_ai_on: LOCAL_AI=yes, or auto
# with a graphics card of about 4 GB or more); otherwise ollama is turned off.
# This step owns /etc/systemd/system/ollama.service.d/ultron.conf; your own tuning goes in another drop-in
# in that folder (e.g. local.conf), which no step writes.

# _ai_gpu_index: the Vulkan device ollama should use, from OLLAMA_GPU (empty = no pin).
_ai_gpu_index() {
  local want types=() i
  conf_var want OLLAMA_GPU
  case $want in
  none) return 0 ;;
  auto) ;;
  *)
    if [[ "$want" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$want"
    else
      warn "OLLAMA_GPU='$want' isn't auto, none or a device number: ollama picks its own GPU"
    fi
    return 0
    ;;
  esac
  have vulkaninfo || return 0
  mapfile -t types < <(vulkaninfo --summary 2>/dev/null | sed -n -E 's/^[[:space:]]*deviceType[[:space:]]*=[[:space:]]*([A-Z_]+).*/\1/p' || true)
  ((${#types[@]} > 1)) || return 0
  for i in "${!types[@]}"; do
    if [[ "${types[$i]}" == PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  warn "More than one Vulkan device but no discrete GPU: ollama picks its own (set OLLAMA_GPU to a number to choose)"
}

# _ai_off: ollama off, with why (LOCAL_AI=no, or auto without a big enough graphics card).
_ai_off() {
  local why
  conf_var why LOCAL_AI
  if [[ "$why" == auto ]]; then why="no graphics card with 4 GB or more was found"; else why="LOCAL_AI=$why"; fi
  if systemctl list-unit-files ollama.service >/dev/null 2>&1 && systemctl is-enabled -q ollama 2>/dev/null; then
    say "Local AI is off ($why): turning ollama off"
    sudo systemctl disable --now ollama
  else
    echo "  Local AI is off ($why): no local model (ultron conf set LOCAL_AI yes to add one anyway)"
  fi
}

step_ai() {
  local model dropin=/etc/systemd/system/ollama.service.d/ultron.conf idx tmp changed=0
  if ! local_ai_on; then
    _ai_off
    return 0
  fi
  have ollama || die "ollama isn't installed: run ultron install packages ai"
  model=$(ask_model)

  if ! id -nG ollama 2>/dev/null | tr ' ' '\n' | grep -qx render; then
    say "Letting ollama use the GPU (render and video groups)"
    sudo usermod -aG render,video ollama
    changed=1
  fi

  idx=$(_ai_gpu_index)
  tmp=$(mktemp)
  cat "$ULTRON_ROOT/system/etc/systemd/system/ollama.service.d/ultron.conf" >"$tmp"
  if [[ -n "$idx" ]]; then
    say "Pinning ollama to Vulkan device $idx"
    printf 'Environment=GGML_VK_VISIBLE_DEVICES=%s\n' "$idx" >>"$tmp"
  fi
  if ! cmp -s "$tmp" "$dropin"; then
    install_root "$tmp" "$dropin" 0644
    sudo systemctl daemon-reload
    changed=1
  fi
  rm -f "$tmp"

  sudo systemctl enable ollama
  # A restart kills running `ask` and commit calls: only when its settings changed.
  if ((changed)); then
    say "Restarting ollama (its settings changed)"
    sudo systemctl restart ollama
  else
    sudo systemctl start ollama
  fi
  local i
  for ((i = 0; i < 30; i++)); do
    if curl -fs http://127.0.0.1:11434/api/version >/dev/null 2>&1; then break; fi
    sleep 1
  done
  curl -fs http://127.0.0.1:11434/api/version >/dev/null 2>&1 || die "ollama didn't answer on 127.0.0.1:11434 (journalctl -u ollama)."

  if [[ "${ULTRON_SKIP_MODEL:-0}" == 1 ]]; then
    warn "ULTRON_SKIP_MODEL=1: not pulling $model"
    return 0
  fi
  say "Pulling $model"
  if ! ollama pull "$model"; then
    if ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qxF -- "$model"; then
      warn "ollama pull failed; keeping the $model already here"
    else
      die "ollama pull $model failed; check ASK_MODEL (ultron conf get ASK_MODEL), then rerun: ultron install ai"
    fi
  fi
}
