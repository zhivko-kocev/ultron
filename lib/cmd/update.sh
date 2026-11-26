# shellcheck shell=bash
# ultron update [--no-pull]: pull ultron, upgrade packages, reinstall, upgrade AUR packages and mise tools
# (Jocasta among them), check. The sudo ticket is dropped before any AUR package is built.

# shellcheck source=install.sh
source "$ULTRON_ROOT/lib/cmd/install.sh"

# _update_pacman: pacman -Syu. SwayFX is built against one wlroots version, so a repository upgrade can
# refuse to go ahead because of it: then SwayFX is swapped for stock sway and rebuilt after the AUR phase.
_update_pacman() {
  local log rc=0
  log=$(mktemp)
  sudo pacman -Syu --noconfirm 2>&1 | tee "$log" || rc=$?
  if ((rc != 0)) && grep -q swayfx "$log"; then
    warn "SwayFX holds back the upgrade: switching to stock sway for now (SwayFX is rebuilt below)"
    rc=0
    sudo pacman -Rdd --noconfirm swayfx || rc=$?
    if ((rc == 0)); then sudo pacman -Syu --noconfirm sway || rc=$?; fi
  fi
  rm -f "$log"
  ((rc == 0)) || die "pacman -Syu failed (see above)."
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

  # 2. Repository upgrade (snap-pac takes snapshots before and after), then the root steps: the default
  # steps except preflight, aur (it builds third-party code), agents and jocasta (they run mise's tools).
  confirm_checkout
  pkg_lock
  sudo_keepalive
  say "Upgrading packages from the Arch repositories (pacman -Syu)"
  _update_pacman
  local steps=() s
  for s in "${ULTRON_DEFAULT_STEPS[@]}"; do
    _in_list "$s" preflight aur agents jocasta || steps+=("$s")
  done
  # The desktop step installs SwayFX only after the AUR phase below, without the ticket.
  _DESKTOP_FX_AFTER_AUR=1
  run_steps "${steps[@]}"
  _DESKTOP_FX_AFTER_AUR=0

  sudo_drop

  # 3. AUR packages, without the ticket: yay asks for the password itself when a package was built.
  run_steps aur
  say "Upgrading AUR packages (yay -Sua)"
  yay -Sua --noconfirm || warn "yay -Sua failed (see above): the AUR packages it names stay at their old versions"
  # SwayFX when EFFECTS=yes and it's missing (swapped out by _update_pacman, or an earlier build failed).
  # shellcheck source=../install/desktop.sh
  source "$ULTRON_ROOT/lib/install/desktop.sh"
  # shellcheck source=apply.sh
  source "$ULTRON_ROOT/lib/cmd/apply.sh"
  _desktop_effects
  _apply_effects

  # 4. Agent tools and the rest of mise (Jocasta too), without sudo.
  local jv_before="" jv_after=""
  jv_before=$(jocasta --version 2>/dev/null || true)
  run_steps agents
  say "Upgrading mise tools"
  mise_gh upgrade || warn "mise upgrade failed (see above)"
  run_steps jocasta
  jv_after=$(jocasta --version 2>/dev/null || true)
  if [[ -n "$jv_before" && "$jv_after" != "$jv_before" ]] && jocasta_running; then
    say "Jocasta was updated: quit it (Ctrl+B, Alt+Q), then press Super+B."
  fi

  run_hook post-update
  # The desktop step rewrote the configs without reloading: pick them up in a running session.
  if in_sway; then swaymsg reload >/dev/null 2>&1 || true; fi

  # 5. Check.
  local rc=0
  "$ULTRON_ROOT/bin/ultron" doctor || rc=1

  # 6. Kernel replaced?
  if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    say "reboot needed: the running kernel was updated"
  fi
  return "$rc"
}
