# shellcheck shell=bash
# ultron update [--no-pull]: pull ultron, reinstall, upgrade packages and tools, rebuild Jocasta, check.

# shellcheck source=install.sh
source "$ULTRON_ROOT/lib/cmd/install.sh"
# shellcheck source=../install/aur.sh
source "$ULTRON_ROOT/lib/install/aur.sh"

# _update_packages: yay -Syu, with the quirk packages held back and rebuilt with their fixes.
_update_packages() {
  local p held=() ignore=() pending=()
  for p in "${AUR_QUIRK_PKGS[@]}"; do
    if pacman -Q "$p" >/dev/null 2>&1; then held+=("$p"); fi
  done
  if ((${#held[@]})); then ignore=(--ignore "$(
    IFS=,
    printf '%s' "${held[*]}"
  )"); fi
  say "Upgrading packages (yay -Syu)"
  yay -Syu "${ignore[@]}" || die "yay -Syu failed (see above)."
  ((${#held[@]})) || return 0
  mapfile -t pending < <({ yay -Qua 2>/dev/null || true; } | awk '{ print $1 }')
  for p in "${held[@]}"; do
    _in_list "$p" "${pending[@]}" || continue
    say "Rebuilding $p (it needs a build fix)"
    aur_install_quirk "$p" || warn "Rebuilding $p failed (see above); the installed version stays"
  done
}

_update_jocasta() {
  [[ -d "$JOCASTA_DIR/.git" ]] || return 0
  # Reinstalling under a running Jocasta breaks it (review item R10), so it waits until Jocasta is closed.
  if jocasta_running; then
    warn "Jocasta is running, so it wasn't updated. Close it (Ctrl+B, Alt+Q), run ultron update again from a terminal, then press Super+B."
    return 0
  fi
  if [[ "$(git -C "$JOCASTA_DIR" branch --show-current)" != main || -n "$(git -C "$JOCASTA_DIR" status --porcelain)" ]]; then
    warn "$JOCASTA_DIR isn't on a clean main: not updating it"
    return 0
  fi
  local before after
  before=$(git -C "$JOCASTA_DIR" rev-parse HEAD)
  git -C "$JOCASTA_DIR" pull --ff-only || warn "Couldn't pull $JOCASTA_DIR"
  after=$(git -C "$JOCASTA_DIR" rev-parse HEAD)
  if [[ "$before" == "$after" ]]; then
    ok "Jocasta is up to date"
    return 0
  fi
  say "Jocasta changed ($before -> $after): rebuilding"
  run_steps jocasta
  say "Quit Jocasta (Ctrl+B, Alt+Q), then press Super+B to start the new build"
}

cmd_update() {
  local pull=1
  case ${1:-} in
  --no-pull) pull=0 ;;
  "") ;;
  *) die "usage: ultron update [--no-pull]" ;;
  esac
  ((EUID != 0)) || die "Run ultron update as your user, not root."

  # 1. Pull ultron when the checkout is clean; new code runs from the start.
  if ((pull)); then
    if [[ -z "$(git -C "$ULTRON_ROOT" status --porcelain 2>/dev/null || echo dirty)" ]]; then
      local before after
      before=$(git -C "$ULTRON_ROOT" rev-parse HEAD)
      say "Pulling ultron"
      git -C "$ULTRON_ROOT" pull --ff-only || warn "git pull failed; continuing with the current checkout"
      after=$(git -C "$ULTRON_ROOT" rev-parse HEAD)
      if [[ "$before" != "$after" ]]; then
        say "ultron changed: restarting the update with the new code"
        exec "$ULTRON_ROOT/bin/ultron" update --no-pull
      fi
    else
      warn "ultron has local changes, so it isn't pulled (updates are paused until you commit or discard them)"
    fi
  fi

  # 2. Root steps: the default steps except preflight, agents and verify.
  confirm_checkout
  sudo_keepalive
  local steps=() s
  for s in "${ULTRON_DEFAULT_STEPS[@]}"; do
    _in_list "$s" preflight agents verify || steps+=("$s")
  done
  run_steps "${steps[@]}"

  # 3. System and AUR upgrade (snap-pac takes snapshots before and after).
  _update_packages

  # 4. Jocasta from main (its step drops the sudo ticket itself).
  _update_jocasta
  sudo_drop

  # 5. Agent tools and the rest of mise, without sudo.
  run_steps agents
  say "Upgrading mise tools"
  mise_gh upgrade || warn "mise upgrade failed (see above)"

  run_hook post-update
  # The desktop step rewrote the configs without reloading: pick them up in a running session.
  if in_sway; then swaymsg reload >/dev/null 2>&1 || true; fi

  # 6. Check.
  local rc=0
  "$ULTRON_ROOT/bin/ultron" doctor || rc=1

  # 7. Kernel replaced?
  if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    say "reboot needed: the running kernel was updated"
  fi
  return "$rc"
}
