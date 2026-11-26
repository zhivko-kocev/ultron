# shellcheck shell=bash
# step dotfiles: the personal dotfiles repo (zsh, git, mise, Zed, agent rules) and its installer.

step_dotfiles() {
  local dir=$HOME/Projects/dotfiles
  if [[ ! -d "$dir/.git" ]]; then
    say "Cloning $DOTFILES_REPO_URL to ~/Projects/dotfiles"
    git clone "$DOTFILES_REPO_URL" "$dir" || die "Couldn't clone the dotfiles repo."
  fi
  say "Running the dotfiles installer"
  bash "$dir/install.sh" || die "The dotfiles installer failed (see above)."
}
