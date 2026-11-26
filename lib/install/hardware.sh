# shellcheck shell=bash
# step hardware: drivers and tools for what this machine has: GPU vendor (from sysfs), laptop, Bluetooth.

# _hw_gpu_vendors: PCI vendor IDs of display controllers (class 0x03xxxx), one per line, unique.
_hw_gpu_vendors() {
  local dev class vendor
  for dev in /sys/bus/pci/devices/*; do
    [[ -r "$dev/class" && -r "$dev/vendor" ]] || continue
    class=$(<"$dev/class") vendor=$(<"$dev/vendor")
    if [[ "$class" == 0x03* ]]; then printf '%s\n' "$vendor"; fi
  done | sort -u
}

step_hardware() {
  local pkgs=() found=() vendor
  while IFS= read -r vendor; do
    case $vendor in
    0x8086)
      found+=("Intel GPU")
      pkgs+=(vulkan-intel intel-media-driver)
      ;;
    0x1002)
      found+=("AMD GPU")
      pkgs+=(vulkan-radeon)
      ;;
    0x10de)
      found+=("NVIDIA GPU")
      warn "NVIDIA GPU: ultron runs it on the open nouveau driver (in mesa). The proprietary NVIDIA driver with sway is untested here."
      ;;
    *) found+=("GPU of vendor $vendor (no extra driver)") ;;
    esac
  done < <(_hw_gpu_vendors)

  local laptop=0 bt=0
  if is_laptop; then
    laptop=1
    found+=("laptop battery")
    pkgs+=(brightnessctl power-profiles-daemon)
  fi
  if compgen -G "/sys/class/bluetooth/hci*" >/dev/null; then
    bt=1
    found+=("Bluetooth adapter")
    pkgs+=(bluez bluez-utils bluetui)
  fi

  if ((${#found[@]} == 0)); then
    echo "  Detected: nothing that needs extra packages"
  else
    printf '  Detected: %s\n' "$(printf '%s, ' "${found[@]}" | sed 's/, $//')"
  fi
  if ((${#pkgs[@]})); then
    say "Installing ${pkgs[*]}"
    pacman_install "${pkgs[@]}" || die "pacman failed (see above); rerun: ultron install hardware"
  fi
  if ((laptop)); then
    say "Enabling power-profiles-daemon (power modes for the battery)"
    sudo systemctl enable --now power-profiles-daemon
  fi
  if ((bt)); then
    say "Enabling Bluetooth (bluetui to pair devices)"
    sudo systemctl enable --now bluetooth
  fi
}
