# shellcheck shell=bash
# ultron update: pull ultron, reinstall, upgrade packages and tools, rebuild Jocasta, check.

# shellcheck source=install.sh
source "$ULTRON_ROOT/lib/cmd/install.sh"

cmd_update() {
  ((EUID != 0)) || die "Run ultron update as your user, not root."

  # 1. Pull ultron when the checkout is clean.
  if [[ -z "$(git -C "$ULTRON_ROOT" status --porcelain)" ]]; then
    say "Pulling ultron"
    git -C "$ULTRON_ROOT" pull --ff-only || warn "git pull failed; continuing with the current checkout"
  else
    warn "ultron has local changes: not pulling"
  fi

  # 2. Default install steps except preflight (and verify: doctor runs in step 6).
  sudo_keepalive
  local steps=() s
  for s in "${ULTRON_DEFAULT_STEPS[@]}"; do
    [[ "$s" == preflight || "$s" == verify ]] || steps+=("$s")
  done
  run_steps "${steps[@]}"

  # 3. System and AUR upgrade (snap-pac takes snapshots before and after).
  say "Upgrading packages (yay -Syu)"
  yay -Syu || die "yay -Syu failed (see above)."

  # 4. mise tools.
  say "Upgrading mise tools"
  mise_gh upgrade || warn "mise upgrade failed (see above)"

  # 5. Jocasta from main.
  # Reinstalling under a running Jocasta breaks it (review item R10), so it waits until Jocasta is closed.
  if [[ -d "$JOCASTA_DIR/.git" ]] && jocasta_running; then
    warn "Jocasta is running, so it wasn't updated. Close it (Ctrl+B, Alt+Q), run ultron update again from a terminal, then press Super+B."
  elif [[ -d "$JOCASTA_DIR/.git" ]]; then
    if [[ "$(git -C "$JOCASTA_DIR" branch --show-current)" == main && -z "$(git -C "$JOCASTA_DIR" status --porcelain)" ]]; then
      local before after
      before=$(git -C "$JOCASTA_DIR" rev-parse HEAD)
      git -C "$JOCASTA_DIR" pull --ff-only || warn "Couldn't pull ~/Projects/jocasta"
      after=$(git -C "$JOCASTA_DIR" rev-parse HEAD)
      if [[ "$before" != "$after" ]]; then
        say "Jocasta changed ($before -> $after): rebuilding"
        run_steps jocasta
        say "Quit Jocasta (Ctrl+B, Alt+Q), then press Super+B to start the new build"
      else
        ok "Jocasta is up to date"
      fi
    else
      warn "$JOCASTA_DIR isn't on a clean main: not updating it"
    fi
  fi

  # 6. Check.
  local rc=0
  "$ULTRON_ROOT/bin/ultron" doctor || rc=1

  # 7. Kernel replaced?
  if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    say "reboot needed: the running kernel was updated"
  fi
  return "$rc"
}
