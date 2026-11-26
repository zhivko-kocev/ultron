# shellcheck shell=bash
# step desktop: stow home/ into ~, the ultron command, generated configs (theme, settings), keyring,
# folders, default apps, and a starter zsh config for people without dotfiles.

# Real directories (never stow-folded), so other tools and ultron apply can add files beside the links.
_desktop_dirs() {
  mkdir -p "$HOME/.config" \
    "$HOME"/.config/{gtk-3.0,gtk-4.0,environment.d,systemd/user,mise,git,sway,foot,fuzzel,mako,swaylock} \
    "$ULTRON_CONF_DIR"/{conf.d,sway,themes,hooks,generated} "$ULTRON_STATE" \
    "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share/applications" "$HOME/.agents/skills"
}

# _desktop_prune: remove dangling links into $ULTRON_ROOT/home/, left behind by packages ultron
# no longer ships (stow -R only cleans packages it is told about).
_desktop_prune() {
  local home link target d dirs=()
  home="$(realpath "$ULTRON_ROOT")/home/"
  for d in "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share/applications" "$HOME/.agents"; do
    if [[ -d "$d" ]]; then dirs+=("$d"); fi
  done
  ((${#dirs[@]})) || return 0
  while IFS= read -r -d '' link; do
    target=$(realpath -m -- "$link") || continue
    if [[ "$target" == "$home"* ]]; then
      rm -f -- "$link"
      echo "  removed old link ~/${link#"$HOME"/}"
    fi
  done < <(find "${dirs[@]}" -maxdepth 4 -xtype l -print0 2>/dev/null)
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
  left=$(stow_conflicts "$dir" "$@" || true)
  if [[ -n "$left" ]]; then
    die "stow still has conflicts, move these away by hand and rerun: $left"
  fi
  stow --no-folding -d "$dir" -t "$HOME" -R "$@" || die "stow failed (see above)"
}

_desktop_keyring() {
  local d=$HOME/.local/share/keyrings
  mkdir -p "$d"
  chmod 700 "$d"
  if [[ ! -e "$d/Default_keyring.keyring" ]]; then
    say "Creating the passwordless Default keyring (keeps browser and gh logins)"
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

# _desktop_shell: a starter zsh config, only for people who have none (dotfiles run earlier).
_desktop_shell() {
  local shell
  if [[ -e "$HOME/.zshrc" || -L "$HOME/.zshrc" ]]; then return 0; fi
  say "No ~/.zshrc: installing ultron's starter zsh config"
  install -m 644 "$ULTRON_ROOT/skel/.zshrc" "$HOME/.zshrc"
  if [[ ! -e "$HOME/.zshenv" && ! -L "$HOME/.zshenv" ]]; then
    install -m 644 "$ULTRON_ROOT/skel/.zshenv" "$HOME/.zshenv"
  fi
  shell=$(getent passwd "$ULTRON_USER" | cut -d: -f7)
  if [[ "$shell" != */zsh ]]; then
    say "Making zsh your login shell"
    sudo chsh -s /usr/bin/zsh "$ULTRON_USER" || warn "chsh failed: run 'chsh -s /usr/bin/zsh' yourself"
  fi
}

step_desktop() {
  local home=$ULTRON_ROOT/home pkgs=() d
  _desktop_dirs
  _desktop_prune
  for d in "$home"/*/; do
    d=${d%/}
    pkgs+=("${d##*/}")
  done
  say "Linking desktop configs with stow: ${pkgs[*]}"
  stow_packages "$home" "$HOME/.ultron-backup" "${pkgs[@]}"

  ln -sfn "$ULTRON_ROOT/bin/ultron" "$HOME/.local/bin/ultron"
  ok "$HOME/.local/bin/ultron -> $ULTRON_ROOT/bin/ultron"

  say "Writing the theme and settings into the app configs"
  # shellcheck source=../cmd/apply.sh
  source "$ULTRON_ROOT/lib/cmd/apply.sh"
  cmd_apply --no-reload

  _desktop_keyring
  xdg-user-dirs-update
  mkdir -p "$HOME/Pictures/Screenshots"
  _desktop_mime
  _desktop_shell
}
