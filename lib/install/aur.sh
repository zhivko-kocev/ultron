# shellcheck shell=bash
# step aur: yay (from yay-bin), then every package in packages/aur.txt.

step_aur() {
  if ! have yay; then
    say "Building yay from the AUR (yay-bin)"
    local tmp
    tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" || die "Couldn't clone yay-bin from the AUR."
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm) || {
      rm -rf "$tmp"
      die "Building yay failed: read the error above, then rerun: ultron install aur"
    }
    rm -rf "$tmp"
  fi
  local pkgs=() p rest=() yayopts=(--needed --noconfirm --answerdiff None --answerclean None --removemake)
  mapfile -t pkgs < <(list_packages "$ULTRON_ROOT/packages/aur.txt")
  say "Installing ${#pkgs[@]} AUR packages with yay (the Limine tools download GraalVM; stremio-service builds Rust)"
  for p in "${pkgs[@]}"; do [[ $p == stremio-service ]] || rest+=("$p"); done
  yay -S "${yayopts[@]}" "${rest[@]}" ||
    die "An AUR build failed: rerun ultron install aur (see docs/migrate.md for the Limine tools and docker-rootless-extras contingencies)."
  if ((${#rest[@]} < ${#pkgs[@]})); then
    # Its openssl-sys only builds against OpenSSL 1.1/3.x; Arch's openssl is 4.x, openssl-3 sits beside it.
    # Its test build (check()) doesn't compile at 0.1.22, so the tests are skipped (--nocheck).
    PKG_CONFIG_PATH=/usr/lib/openssl-3/pkgconfig yay -S "${yayopts[@]}" --mflags --nocheck stremio-service ||
      die "Building stremio-service failed: rerun ultron install aur."
  fi
}
