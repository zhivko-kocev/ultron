# shellcheck shell=bash
# ultron power: lock, suspend, log out, reboot, reboot to BIOS, shut down.

cmd_power() {
  source "$ULTRON_ROOT/lib/cmd/close.sh"
  local choice
  choice=$(printf '%s\n' Lock Suspend "Log out" Reboot "Reboot to BIOS" "Shut down" |
    fuzzel --dmenu --lines 6 --prompt "power ▸ ") || return 0
  case $choice in
  Lock) "$ULTRON_ROOT/bin/ultron" lock ;;
  Suspend) systemctl suspend ;;
  "Log out" | Reboot | "Reboot to BIOS" | "Shut down")
    if jocasta_running; then
      _confirm "$choice? Jocasta is running: its threads stop (they resume next time)" || return 0
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
