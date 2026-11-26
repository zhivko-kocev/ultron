# shellcheck shell=bash
# step desktop: stow home/ into ~, the ultron command, keyring, folders, dark mode, default apps.

# Real directories (never stow-folded), so other tools can add files beside ultron's links.
_desktop_dirs() {
  mkdir -p "$HOME/.config" \
    "$HOME"/.config/{gtk-3.0,gtk-4.0,environment.d,systemd/user,mise,git,ultron} \
    "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share/applications" "$HOME/.agents/skills"
}

# stow_conflicts DIR PACKAGE...: target paths (relative to ~) a stow run would refuse to overwrite.
stow_conflicts() {
  local dir=$1
  shift
  stow -n -v --no-folding -d "$dir" -t "$HOME" -R "$@" 2>&1 | sed -n -E \
    -e 's/.*over existing target (.+) since .*/\1/p' \
    -e 's/.*existing target is stowed to a different package: (.+) => .*/\1/p' \
    -e 's/.*existing target is (neither a link nor a directory|not owned by stow): (.+)$/\2/p' |
    sort -u
}

# stow_packages DIR BACKUP_ROOT PACKAGE...: move conflicting files to BACKUP_ROOT/<stamp>/<path>, then stow.
stow_packages() {
  local dir=$1 backup rel left
  backup=$2/$(date -u +%Y%m%dT%H%M%SZ)
  shift 2
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] || continue
    mkdir -p "$backup/$(dirname "$rel")"
    mv "$HOME/$rel" "$backup/$rel"
    echo "  moved ~/$rel to $backup/$rel"
  done < <(stow_conflicts "$dir" "$@")
  left=$(stow_conflicts "$dir" "$@")
  [[ -z "$left" ]] || die "stow still has conflicts, move these away by hand and rerun: $left"
  stow --no-folding -d "$dir" -t "$HOME" -R "$@" || die "stow failed (see above)"
}

_desktop_keyring() {
  local d=$HOME/.local/share/keyrings
  mkdir -p "$d"
  chmod 700 "$d"
  if [[ ! -e "$d/Default_keyring.keyring" ]]; then
    say "Creating the passwordless Default keyring (logins for Chrome and gh)"
    printf '[keyring]\ndisplay-name=Default keyring\nctime=%s\nmtime=0\nlock-on-idle=false\nlock-after=false\n' \
      "$(date +%s)" >"$d/Default_keyring.keyring"
    chmod 600 "$d/Default_keyring.keyring"
  fi
  if [[ ! -e "$d/default" ]]; then
    printf 'Default_keyring\n' >"$d/default"
    chmod 644 "$d/default"
  fi
}

_desktop_mime() {
  say "Setting default apps"
  local t
  for t in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
    xdg-mime default ultron-browser.desktop "$t"
  done
  for t in image/png image/jpeg image/gif image/webp image/bmp image/tiff; do
    xdg-mime default imv.desktop "$t"
  done
  for t in video/mp4 video/x-matroska video/webm video/quicktime video/mpeg audio/flac audio/ogg video/ogg; do
    xdg-mime default mpv.desktop "$t"
  done
  xdg-mime default org.pwmt.zathura-pdf-mupdf.desktop application/pdf
  xdg-mime default thunar.desktop inode/directory
}

step_desktop() {
  local home=$ULTRON_ROOT/home pkgs=() d
  _desktop_dirs
  for d in "$home"/*/; do
    d=${d%/}
    pkgs+=("${d##*/}")
  done
  say "Linking desktop configs with stow: ${pkgs[*]}"
  stow_packages "$home" "$HOME/.ultron-backup" "${pkgs[@]}"

  ln -sfn "$ULTRON_ROOT/bin/ultron" "$HOME/.local/bin/ultron"
  ok "$HOME/.local/bin/ultron -> $ULTRON_ROOT/bin/ultron"

  _desktop_keyring
  xdg-user-dirs-update
  mkdir -p "$HOME/Pictures/Screenshots"
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null ||
    warn "gsettings failed (no session bus yet); dark mode for GTK4 apps applies after rerunning in sway"
  _desktop_mime

  if [[ "$(conf_get BOSS)" == "" ]]; then
    conf_set BOSS omp
    ok "Wrote BOSS=omp to $ULTRON_CONF"
  fi
}
