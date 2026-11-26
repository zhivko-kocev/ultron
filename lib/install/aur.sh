# shellcheck shell=bash
# step aur: yay (from yay-bin), packages/aur.txt, then your ~/.config/ultron/packages.txt
# (yay resolves official and AUR names alike).

AUR_YAY_OPTS=(--needed --noconfirm --answerdiff None --answerclean None --removemake)

# Packages that don't build with plain `yay -S`; aur_quirk fills the fix for one of them.
AUR_QUIRK_PKGS=(stremio-service)

# aur_quirk PKG: sets _Q_PRE (packages to install first), _Q_ENV (build environment) and _Q_FLAGS
# (extra yay options); 1 when PKG builds without help.
aur_quirk() {
  _Q_PRE=() _Q_ENV=() _Q_FLAGS=()
  case $1 in
  stremio-service)
    # Its openssl-sys only builds against OpenSSL 1.1/3.x; Arch's openssl is 4.x, openssl-3 sits beside it.
    # Its test build (check()) doesn't compile at 0.1.22, so the tests are skipped (--nocheck). Its LTO build
    # takes ~3 GB per rustc: two jobs keep it out of the OOM killer on smaller machines (seen in a 6 GB VM).
    _Q_PRE=(openssl-3)
    _Q_ENV=(PKG_CONFIG_PATH=/usr/lib/openssl-3/pkgconfig CARGO_BUILD_JOBS=2)
    _Q_FLAGS=(--mflags --nocheck)
    ;;
  *) return 1 ;;
  esac
}

# aur_install_quirk PKG: build and install a package from AUR_QUIRK_PKGS with its fix.
aur_install_quirk() {
  aur_quirk "$1" || return 1
  if ((${#_Q_PRE[@]})); then pacman_install "${_Q_PRE[@]}" || return 1; fi
  env "${_Q_ENV[@]}" yay -S "${AUR_YAY_OPTS[@]}" "${_Q_FLAGS[@]}" "$1"
}

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
  local file=$ULTRON_CONF_DIR/packages.txt pkgs=() plain=() failed=() p
  [[ -f "$file" ]] || return 0
  mapfile -t pkgs < <(list_packages "$file")
  ((${#pkgs[@]})) || return 0
  say "Installing your ${#pkgs[@]} packages from $file"
  for p in "${pkgs[@]}"; do
    if _in_list "$p" "${AUR_QUIRK_PKGS[@]}"; then
      aur_install_quirk "$p" || failed+=("$p")
    else
      plain+=("$p")
    fi
  done
  # One yay run for speed; when it fails, one at a time to find the packages that don't install.
  if ((${#plain[@]})) && ! yay -S "${AUR_YAY_OPTS[@]}" "${plain[@]}"; then
    warn "Installing them together failed: trying one at a time"
    for p in "${plain[@]}"; do
      yay -S "${AUR_YAY_OPTS[@]}" "$p" || failed+=("$p")
    done
  fi
  if ((${#failed[@]})); then
    warn "These packages from $file didn't install (see above): ${failed[*]}"
  fi
}

step_aur() {
  _aur_yay
  local pkgs=() p plain=()
  mapfile -t pkgs < <(list_packages "$ULTRON_ROOT/packages/aur.txt")
  say "Installing ${#pkgs[@]} AUR packages with yay (the Limine tools download GraalVM)"
  for p in "${pkgs[@]}"; do
    if _in_list "$p" "${AUR_QUIRK_PKGS[@]}"; then
      aur_install_quirk "$p" || die "Building $p failed (see above); rerun: ultron install aur"
    else
      plain+=("$p")
    fi
  done
  if ((${#plain[@]})); then
    yay -S "${AUR_YAY_OPTS[@]}" "${plain[@]}" ||
      die "An AUR build failed (see above); rerun: ultron install aur"
  fi
  _aur_user_packages
}
