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
  local pkgs=()
  mapfile -t pkgs < <(list_packages "$ULTRON_ROOT/packages/aur.txt")
  say "Installing ${#pkgs[@]} AUR packages with yay (the Limine tools download GraalVM; stremio-service builds Rust)"
  yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "${pkgs[@]}" ||
    die "An AUR build failed: rerun ultron install aur (see docs/migrate.md for the Limine tools and docker-rootless-extras contingencies)."
}
