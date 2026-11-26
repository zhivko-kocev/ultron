# shellcheck shell=bash
# ultron power: lock, suspend, log out, reboot, reboot to BIOS, shut down.

cmd_power() {
  local choice
  choice=$(printf '%s\n' Lock Suspend "Log out" Reboot "Reboot to BIOS" "Shut down" | pick power --lines 6) || return 0
  case $choice in
  Lock) "$ULTRON_ROOT/bin/ultron" lock ;;
  Suspend) systemctl suspend ;;
  "Log out" | Reboot | "Reboot to BIOS" | "Shut down")
    if [[ -n "$(sway_ids '(.app_id // "") == "ultron-boss"')" ]]; then
      confirm "$choice? The boss is running: its agents stop (they resume next time)" || return 0
    fi
    case $choice in
    "Log out") swaymsg exit >/dev/null ;;
    Reboot) systemctl reboot ;;
    "Reboot to BIOS") systemctl reboot --firmware-setup ;;
    "Shut down") systemctl poweroff ;;
    esac
    ;;
  esac
}
