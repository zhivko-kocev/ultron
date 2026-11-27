# shellcheck shell=bash
# step jocasta: Jocasta, the default boss. mise installs it from its GitHub releases with the other agent
# tools (system/etc/mise/conf.d/ultron-tools.toml, step agents); this step runs its first `jocasta setup`,
# lists the folders it looks for projects in, and hands it the theme's colours. No root, no build.

# shellcheck source=../cmd/apply.sh
source "$ULTRON_ROOT/lib/cmd/apply.sh"

step_jocasta() {
  local v boss agent=$HOME/.jocasta/agent projects
  read -r boss _ <<<"$(boss_kind)"
  if [[ "$boss" != jocasta ]]; then
    ok "The boss is $boss, so Jocasta isn't set up (to use it: ultron conf set BOSS jocasta && ultron install jocasta)"
    return 0
  fi
  v=$(jocasta --version 2>/dev/null) ||
    die "jocasta doesn't run: mise installs it with the agent tools (ultron install agents), then rerun: ultron install jocasta"
  ok "$v"

  # Setup keeps one marker per change it applied in ~/.jocasta/agent/setup/; none = it never ran here.
  if ! compgen -G "$agent/setup/*.json" >/dev/null; then
    say "Running jocasta setup --yes (Jocasta's settings for omp, its config and its folders)"
    jocasta setup --yes || die "jocasta setup didn't finish (see above); rerun: ultron install jocasta"
  else
    ok "jocasta setup ran before. When a new Jocasta brings changes, it says so as it starts: run jocasta setup to read and apply them."
  fi

  projects=$agent/projects.yaml
  if [[ ! -e "$projects" ]]; then
    mkdir -p "$agent"
    {
      printf 'version: 1\nroots:\n  - path: %s\n    depth: 1\n' "$HOME/Projects"
      if [[ -d "$HOME/Work" ]]; then printf '  - path: %s\n    depth: 1\n' "$HOME/Work"; fi
    } >"$projects"
    ok "Wrote $projects (Jocasta finds the git repositories in those folders)"
  fi

  local font
  theme_load
  _apply_check_theme
  _apply_font font
  _apply_palette "$font"
}
