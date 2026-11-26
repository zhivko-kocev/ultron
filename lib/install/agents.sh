# shellcheck shell=bash
# step agents: the agent tools pinned in /etc/mise/conf.d/ultron-tools.toml (omp, hunk, node).

step_agents() {
  [[ -r "$ULTRON_TOOLS_CONF" ]] || die "$ULTRON_TOOLS_CONF is missing: run ultron install system first."
  local tools=()
  mapfile -t tools < <(toml_tool_keys "$ULTRON_TOOLS_CONF")
  ((${#tools[@]})) || die "$ULTRON_TOOLS_CONF lists no tools."
  say "Installing agent tools with mise: ${tools[*]}"
  # Only the tools named in the system conf; other mise configs are left alone.
  if ! mise_gh install "${tools[@]}"; then
    # `latest`/`lts` need a release lookup even when installed; a GitHub hiccup mustn't fail an update.
    { omp --version >/dev/null 2>&1 && hunk --version >/dev/null 2>&1; } ||
      die "mise install failed (see above); rerun: ultron install agents"
    warn "mise install failed (see above), but omp and hunk work: keeping the installed versions"
  fi
  mise reshim
  omp --version >/dev/null 2>&1 || die "omp doesn't run after mise install."
  hunk --version >/dev/null 2>&1 || die "hunk doesn't run after mise install."
  ok "omp $(omp --version 2>/dev/null | head -n1), hunk $(hunk --version 2>/dev/null | head -n1)"
  set_omp_settings
}
