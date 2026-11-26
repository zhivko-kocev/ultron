# shellcheck shell=bash
# step jocasta (on demand): build or fetch Jocasta, install it to ~/.local/lib/jocasta,
# pin omp to Jocasta's version, run `jocasta setup`, and make it the boss.

_jocasta_src() {
  local tarball=jocasta-linux-x64.tar.gz from=${ULTRON_JOCASTA_FROM:-} dir
  if [[ -n "$from" ]]; then
    dir=$(mktemp -d)
    say "Getting the Jocasta build from $from" >&2
    if [[ "$from" =~ ^https?:// ]]; then
      { curl -fL --retry 2 -o "$dir/$tarball" "${from%/}/$tarball" >&2 &&
        curl -fL --retry 2 -o "$dir/$tarball.sha256" "${from%/}/$tarball.sha256" >&2; } ||
        die "Couldn't download $tarball (and .sha256) from $from"
    else
      [[ -f "$from/$tarball" && -f "$from/$tarball.sha256" ]] || die "$from has no $tarball and $tarball.sha256"
      cp "$from/$tarball" "$from/$tarball.sha256" "$dir/"
    fi
  else
    is_vm && echo "  VM: building from source (ULTRON_JOCASTA_FROM=http://10.0.2.2:8765 skips the build)" >&2
    local tools=()
    mapfile -t tools < <(toml_tool_keys "$JOCASTA_DIR/mise.toml")
    ((${#tools[@]})) || die "Couldn't read the [tools] of $JOCASTA_DIR/mise.toml"
    say "Building Jocasta (mise tools: ${tools[*]})" >&2
    (
      cd "$JOCASTA_DIR"
      mise trust mise.toml
      mise_gh install --locked "${tools[@]}"
      mise exec -- bun install --frozen-lockfile
      mise run build
    ) >&2 || die "The Jocasta build failed (see above). The omp boss keeps working (BOSS=omp)."
    dir=$JOCASTA_DIR/dist
  fi
  # Check the tarball against its .sha256 (first field is the hash).
  local want got
  want=$(awk '{ print $1; exit }' "$dir/$tarball.sha256")
  got=$(sha256sum "$dir/$tarball" | awk '{ print $1 }')
  [[ -n "$want" && "$want" == "$got" ]] || die "$tarball doesn't match its .sha256 (want $want, got $got)"
  ok "$tarball checksum matches" >&2
  printf '%s\n' "$dir"
}

_jocasta_pin_omp() {
  local want have tools=() tmp
  want=$(grep -oE 'checked against omp [0-9]+(\.[0-9]+)*' "$JOCASTA_DIR/README.md" 2>/dev/null | head -n1 | grep -oE '[0-9]+(\.[0-9]+)*$' || true)
  if [[ -z "$want" ]]; then
    warn "Jocasta's README names no omp version; keeping the current pin ($(omp_pin))"
    return 0
  fi
  have=$(omp_pin)
  if [[ "$want" == "$have" ]]; then
    ok "omp pin already matches Jocasta ($want)"
    return 0
  fi
  say "Pinning omp to $want (Jocasta's README; was ${have:-unset})"
  tmp=$(mktemp)
  sed -E "s/^([[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\"$want\"/" "$ULTRON_TOOLS_CONF" >"$tmp"
  grep -q "oh-my-pi" "$tmp" || printf 'oh-my-pi = "%s"\n' "$want" >>"$tmp"
  install_root "$tmp" "$ULTRON_TOOLS_CONF" 0644
  rm -f "$tmp"
  mapfile -t tools < <(toml_tool_keys "$ULTRON_TOOLS_CONF")
  mise_gh install "${tools[@]}"
  mise reshim
}

step_jocasta() {
  # Installing under a running Jocasta breaks the running copy (review item R10).
  ! jocasta_running || die "Jocasta is running. Close it first (Ctrl+B, Alt+Q), then rerun: ultron install jocasta"

  # 1. Source checkout.
  if [[ ! -d "$JOCASTA_DIR/.git" ]]; then
    say "Cloning $JOCASTA_REPO_URL to ~/Projects/jocasta"
    git clone "$JOCASTA_REPO_URL" "$JOCASTA_DIR" || die "Couldn't clone Jocasta."
  elif [[ "$(git -C "$JOCASTA_DIR" branch --show-current)" == main && -z "$(git -C "$JOCASTA_DIR" status --porcelain)" ]]; then
    say "Updating ~/Projects/jocasta (main, clean)"
    git -C "$JOCASTA_DIR" pull --ff-only || warn "git pull failed; building what's checked out"
  else
    warn "$JOCASTA_DIR isn't on a clean main: building it as it is"
  fi

  # 2. Build or fetch.
  local src
  src=$(_jocasta_src)

  # 3. Install (own folder outside the data dir: review finding R1).
  say "Installing Jocasta to $JOCASTA_INSTALL_DIR"
  JOCASTA_INSTALL_DIR=$JOCASTA_INSTALL_DIR JOCASTA_INSTALL_NO_PATH=1 JOCASTA_INSTALL_FROM=$src \
    sh "$JOCASTA_DIR/scripts/install.sh" || die "Jocasta's install.sh failed (see above)."
  [[ "$src" == "$JOCASTA_DIR/dist" ]] || rm -rf "$src"

  # 4. On PATH.
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$JOCASTA_INSTALL_DIR/jocasta" "$HOME/.local/bin/jocasta"
  "$HOME/.local/bin/jocasta" --version || die "The installed jocasta doesn't run."

  # 5. omp version Jocasta was checked against.
  _jocasta_pin_omp

  # 6. Jocasta's own config (interactive diffs).
  [[ -t 0 && -t 1 ]] || die "jocasta setup is interactive: run ultron install jocasta in a terminal."
  say "Running jocasta setup: read each diff and type y"
  "$HOME/.local/bin/jocasta" setup || die "jocasta setup didn't finish; rerun: ultron install jocasta"

  # 7. Project roots.
  local projects=$HOME/.jocasta/agent/projects.yaml
  if [[ ! -e "$projects" ]]; then
    mkdir -p "${projects%/*}"
    cat >"$projects" <<YAML
version: 1
roots:
  - path: $HOME/Projects
    depth: 1
  - path: $HOME/Work
    depth: 1
YAML
    ok "Wrote $projects"
  fi

  # 8. omp settings (setup may reset them) and the boss.
  set_omp_settings
  conf_set BOSS jocasta
  ok "BOSS=jocasta in $ULTRON_CONF"

  # 9.
  say "Close the old boss window (Super+W on workspace 1), then press Super+B"
}
