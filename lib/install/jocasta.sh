# shellcheck shell=bash
# step jocasta (on demand): build or fetch Jocasta, install it to ~/.local/lib/jocasta,
# pin omp to Jocasta's version, run `jocasta setup`, and make it the boss.
# Its one root change (the omp pin) comes first; the sudo ticket is dropped before anything is built.

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
    if is_vm; then echo "  VM: building from source (ULTRON_JOCASTA_FROM=<url or folder> skips the build)" >&2; fi
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
    ) >&2 || die "The Jocasta build failed (see above). The current boss keeps working."
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

# _jocasta_pin_omp: rewrite the system mise conf to the omp version Jocasta names (root). 0 = pin changed.
_jocasta_pin_omp() {
  # Called as an `if` condition, where set -e is off: every failure dies explicitly.
  local want have tmp
  want=$(jocasta_omp_want)
  have=$(omp_pin)
  if [[ -z "$want" ]]; then
    warn "Jocasta's README names no omp version; keeping the current pin (${have:-unset})"
    return 1
  fi
  if [[ "$want" == "$have" ]]; then
    ok "omp pin already matches Jocasta ($want)"
    return 1
  fi
  [[ -r "$ULTRON_TOOLS_CONF" ]] || die "$ULTRON_TOOLS_CONF is missing: run ultron install system first."
  say "Pinning omp to $want (Jocasta's README; was ${have:-unset})"
  tmp=$(mktemp)
  sed -E "s/^([[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\"$want\"/" "$ULTRON_TOOLS_CONF" >"$tmp" ||
    die "Couldn't read $ULTRON_TOOLS_CONF"
  if ! grep -q "oh-my-pi" "$tmp"; then printf 'oh-my-pi = "%s"\n' "$want" >>"$tmp"; fi
  install_root "$tmp" "$ULTRON_TOOLS_CONF" 0644 || die "Couldn't write $ULTRON_TOOLS_CONF (sudo)."
  rm -f "$tmp"
}

step_jocasta() {
  # Installing under a running Jocasta breaks the running copy (review item R10).
  ! jocasta_running || die "Jocasta is running. Close it first (Ctrl+B, Alt+Q), then rerun: ultron install jocasta"
  [[ -t 0 && -t 1 ]] || die "jocasta setup is interactive: run ultron install jocasta in a terminal."

  # 1. Source checkout.
  if [[ ! -d "$JOCASTA_DIR/.git" ]]; then
    say "Cloning $JOCASTA_REPO_URL to $JOCASTA_DIR"
    mkdir -p "${JOCASTA_DIR%/*}"
    git clone "$JOCASTA_REPO_URL" "$JOCASTA_DIR" || die "Couldn't clone Jocasta."
  elif [[ "$(git -C "$JOCASTA_DIR" branch --show-current)" == main && -z "$(git -C "$JOCASTA_DIR" status --porcelain)" ]]; then
    say "Updating $JOCASTA_DIR (main, clean)"
    git -C "$JOCASTA_DIR" pull --ff-only || warn "git pull failed; building what's checked out"
  else
    warn "$JOCASTA_DIR isn't on a clean main: building it as it is"
  fi

  # 2. The only root part, then no more sudo: everything after runs third-party code.
  local pinned=0
  if _jocasta_pin_omp; then pinned=1; fi
  sudo_drop
  if ((pinned)); then
    local tools=()
    mapfile -t tools < <(toml_tool_keys "$ULTRON_TOOLS_CONF")
    mise_gh install "${tools[@]}" || die "mise couldn't install the pinned omp (see above); rerun: ultron install jocasta"
    mise reshim
  fi

  # 3. Build or fetch.
  local src
  src=$(_jocasta_src)

  # 4. Install (own folder outside the data dir: review finding R1).
  say "Installing Jocasta to $JOCASTA_INSTALL_DIR"
  JOCASTA_INSTALL_DIR=$JOCASTA_INSTALL_DIR JOCASTA_INSTALL_NO_PATH=1 JOCASTA_INSTALL_FROM=$src \
    sh "$JOCASTA_DIR/scripts/install.sh" || die "Jocasta's install.sh failed (see above)."
  if [[ "$src" != "$JOCASTA_DIR/dist" ]]; then rm -rf "$src"; fi

  # 5. On PATH.
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$JOCASTA_INSTALL_DIR/jocasta" "$HOME/.local/bin/jocasta"
  "$HOME/.local/bin/jocasta" --version || die "The installed jocasta doesn't run."

  # 6. Jocasta's own config (interactive diffs).
  say "Running jocasta setup: read each diff and type y"
  "$HOME/.local/bin/jocasta" setup || die "jocasta setup didn't finish; rerun: ultron install jocasta"

  # 7. Project roots.
  local projects=$HOME/.jocasta/agent/projects.yaml
  if [[ ! -e "$projects" ]]; then
    mkdir -p "${projects%/*}"
    {
      printf 'version: 1\nroots:\n  - path: %s\n    depth: 1\n' "$HOME/Projects"
      if [[ -d "$HOME/Work" ]]; then printf '  - path: %s\n    depth: 1\n' "$HOME/Work"; fi
    } >"$projects"
    ok "Wrote $projects"
  fi

  # 8. omp settings (setup may reset them) and the boss.
  set_omp_settings
  conf_set BOSS jocasta
  ok "BOSS=jocasta in $ULTRON_CONF"

  # 9.
  say "Close the old boss window (Super+W on workspace 1), then press Super+B"
}
