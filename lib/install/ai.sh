# shellcheck shell=bash
# step ai: ollama on the RX 580 (Vulkan), the qwen3:4b model, and omp's commit role.

# _ai_gpu_index: Vulkan index of the RX 580 when more than one GPU is listed (empty otherwise).
_ai_gpu_index() {
  local names=() i
  have vulkaninfo || return 0
  mapfile -t names < <(vulkaninfo --summary 2>/dev/null | sed -n -E 's/^[[:space:]]*deviceName[[:space:]]*=[[:space:]]*(.*)$/\1/p')
  ((${#names[@]} > 1)) || return 0
  for i in "${!names[@]}"; do
    if [[ "${names[$i]^^}" =~ RX[[:space:]]*580|POLARIS ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  warn "More than one GPU, but none is an RX 580: ollama picks its own (${names[*]})"
}

step_ai() {
  local dropin=/etc/systemd/system/ollama.service.d/ultron.conf idx tmp
  say "Letting ollama use the GPU (render and video groups)"
  sudo usermod -aG render,video ollama

  idx=$(_ai_gpu_index)
  tmp=$(mktemp)
  cat "$ULTRON_ROOT/system/etc/systemd/system/ollama.service.d/ultron.conf" >"$tmp"
  if [[ -n "$idx" ]]; then
    say "Pinning ollama to Vulkan device $idx (the RX 580)"
    printf 'Environment=GGML_VK_VISIBLE_DEVICES=%s\n' "$idx" >>"$tmp"
  fi
  install_root "$tmp" "$dropin" 0644
  rm -f "$tmp"

  say "Starting ollama"
  sudo systemctl daemon-reload
  sudo systemctl enable ollama
  sudo systemctl restart ollama
  local i
  for ((i = 0; i < 30; i++)); do
    curl -fs http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fs http://127.0.0.1:11434/api/version >/dev/null 2>&1 || die "ollama didn't answer on 127.0.0.1:11434 (journalctl -u ollama)."

  if [[ "${ULTRON_SKIP_MODEL:-0}" == 1 ]]; then
    warn "ULTRON_SKIP_MODEL=1: not pulling qwen3:4b"
  else
    say "Pulling qwen3:4b (about 2.5 GB)"
    ollama pull qwen3:4b || die "ollama pull failed; rerun: ultron install ai"
  fi
  set_commit_role
}
