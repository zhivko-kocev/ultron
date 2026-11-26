# shellcheck shell=bash
# step dotfiles: your own dotfiles repo (DOTFILES_REPO), cloned to ~/Projects/dotfiles, and its install.sh.
# It runs early, so the conf.d files, packages.txt and overrides it links are seen by the later steps.

step_dotfiles() {
  local repo origin
  conf_var repo DOTFILES_REPO
  if [[ -z "$repo" ]]; then
    echo "  No dotfiles repo set (to use one: ultron conf set DOTFILES_REPO https://github.com/you/dotfiles)"
    return 0
  fi
  # Its installer typically links with stow and switches the shell to zsh, before the packages step.
  pacman_install git stow zsh || die "Couldn't install git, stow and zsh for the dotfiles installer."
  if [[ ! -e "$DOTFILES_DIR" ]]; then
    say "Cloning $repo to $DOTFILES_DIR"
    mkdir -p "${DOTFILES_DIR%/*}"
    git clone "$repo" "$DOTFILES_DIR" || die "Couldn't clone $repo: check DOTFILES_REPO (ultron conf get DOTFILES_REPO)."
  elif [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    die "$DOTFILES_DIR exists but isn't a git checkout: move it away, then rerun: ultron install dotfiles"
  else
    origin=$(git -C "$DOTFILES_DIR" config --get remote.origin.url 2>/dev/null || true)
    if [[ "$origin" != "$repo" ]]; then
      warn "$DOTFILES_DIR comes from ${origin:-nowhere}, not $repo: using it as it is"
    elif [[ -z "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]]; then
      say "Updating $DOTFILES_DIR"
      git -C "$DOTFILES_DIR" pull --ff-only || warn "git pull failed in $DOTFILES_DIR; using what's checked out"
    else
      warn "$DOTFILES_DIR has local changes: not pulling"
    fi
  fi
  if [[ -f "$DOTFILES_DIR/install.sh" ]]; then
    say "Running $DOTFILES_DIR/install.sh"
    (cd "$DOTFILES_DIR" && bash ./install.sh) || die "The dotfiles installer failed (see above); fix it, then rerun: ultron install dotfiles"
  else
    echo "  $DOTFILES_DIR has no install.sh: nothing to run"
  fi
  # Settings it linked into ~/.config/ultron/conf.d count from here on.
  conf_load
}
