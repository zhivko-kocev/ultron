# shellcheck shell=bash
# step aur: yay (from yay-bin), packages/aur.txt, then your ~/.config/ultron/packages.txt
# (yay resolves official and AUR names alike).

AUR_YAY_OPTS=(--needed --noconfirm --answerdiff None --answerclean None --removemake)

_aur_yay() {
  have yay && return 0
  say "Building yay from the AUR (yay-bin)"
  local tmp
  tmp=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" || die "Couldn't clone yay-bin from the AUR."
  # makepkg -i installs through `sudo -k pacman`, which always asks for the password again; so build only
  # (yay-bin needs nothing beyond base-devel and git) and install with the sudo session ultron already holds.
  (cd "$tmp/yay-bin" && makepkg --noconfirm && sudo pacman -U --noconfirm ./yay-bin-*.pkg.tar.*) || {
    rm -rf "$tmp"
    die "Building yay failed: read the error above, then rerun: ultron install aur"
  }
  rm -rf "$tmp"
}

# _aur_user_packages: your packages.txt; a package that fails is named in a warning, the rest still install.
_aur_user_packages() {
  local file=$ULTRON_CONF_DIR/packages.txt pkgs=() failed=() p
  [[ -f "$file" ]] || return 0
  mapfile -t pkgs < <(list_packages "$file")
  ((${#pkgs[@]})) || return 0
  say "Installing your ${#pkgs[@]} packages from $file"
  # One yay run for speed; when it fails, one at a time to find the packages that don't install.
  if ! yay -S "${AUR_YAY_OPTS[@]}" "${pkgs[@]}"; then
    warn "Installing them together failed: trying one at a time"
    for p in "${pkgs[@]}"; do
      yay -S "${AUR_YAY_OPTS[@]}" "$p" || failed+=("$p")
    done
  fi
  if ((${#failed[@]})); then
    warn "These packages from $file didn't install (see above): ${failed[*]}"
  fi
}

step_aur() {
  _aur_yay
  local pkgs=()
  mapfile -t pkgs < <(list_packages "$ULTRON_ROOT/packages/aur.txt")
  say "Installing ${#pkgs[@]} AUR packages with yay (the Limine tools download GraalVM)"
  yay -S "${AUR_YAY_OPTS[@]}" "${pkgs[@]}" ||
    die "An AUR build failed (see above); rerun: ultron install aur"
  _aur_user_packages
}
