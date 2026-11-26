#!/usr/bin/env bash
# LOCAL_AI: yes and no as said; auto = a card with 3.5 GiB or more (AMD/Intel sysfs or nvidia-smi).
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export ULTRON_ROOT=$PWD XDG_RUNTIME_DIR=$HOME/run ULTRON_SYS_DRM=$HOME/drm
# shellcheck source=../lib/common.sh
source lib/common.sh
mkdir -p "$HOME/bin" "$HOME/drm/card0/device" "$HOME/drm/card0-DP-1"
# nvidia-smi stub: prints $FAKE_NVIDIA_MIB (nothing when it's empty).
# shellcheck disable=SC2016 # the stub expands it, not this script
printf '#!/bin/sh\n[ -n "$FAKE_NVIDIA_MIB" ] && echo "$FAKE_NVIDIA_MIB"\nexit 0\n' >"$HOME/bin/nvidia-smi"
chmod +x "$HOME/bin/nvidia-smi"
export PATH="$HOME/bin:$PATH" FAKE_NVIDIA_MIB=""
want() {
  local got=no
  if local_ai_on; then got=yes; fi
  [[ $got == "$1" ]] || {
    echo "FAIL localai: $2: got $got, want $1"
    exit 1
  }
}
[[ $(conf_get LOCAL_AI) == auto ]] || {
  echo "FAIL localai: the default isn't auto"
  exit 1
}
echo 2147483648 >"$HOME/drm/card0/device/mem_info_vram_total"
want no "auto, 2 GiB card"
echo 8589934592 >"$HOME/drm/card0/device/mem_info_vram_total"
want yes "auto, 8 GiB card"
conf_set LOCAL_AI no
want no "LOCAL_AI=no, 8 GiB card"
rm "$HOME/drm/card0/device/mem_info_vram_total"
conf_set LOCAL_AI yes
want yes "LOCAL_AI=yes, no card"
conf_set LOCAL_AI ""
want no "auto, no card"
FAKE_NVIDIA_MIB=" 3000"
want no "auto, nvidia 3000 MiB"
FAKE_NVIDIA_MIB=$'2048\n 12288'
want yes "auto, second nvidia card 12288 MiB"
echo "localai ok"
