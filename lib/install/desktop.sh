# shellcheck shell=bash
# step desktop: stow home/ into ~, the ultron command, SwayFX or stock sway (EFFECTS), generated configs
# (theme, settings), keyring, folders, default apps, and a starter zsh config for people without dotfiles.

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

# _desktop_mime_viewer APP TYPE...: APP opens TYPE, unless mimeapps.list already names an app for it (your choice stays).
_desktop_mime_viewer() {
  local app=$1 t
  shift
  for t in "$@"; do
    if ! awk -F= -v t="$t" '$1 == t { f = 1 } END { exit !f }' "$HOME/.config/mimeapps.list" 2>/dev/null; then
      xdg-mime default "$app" "$t"
    fi
  done
}

_desktop_mime() {
  say "Setting default apps"
  local t
  # Links always go to the link router (ultron open-url): it sends local pages to the preview browser.
  for t in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
    xdg-mime default ultron-browser.desktop "$t"
  done
  _desktop_mime_viewer imv.desktop image/png image/jpeg image/gif image/webp image/bmp image/tiff
  _desktop_mime_viewer mpv.desktop video/mp4 video/x-matroska video/webm video/quicktime video/mpeg audio/flac audio/ogg video/ogg
  _desktop_mime_viewer org.pwmt.zathura-pdf-mupdf.desktop application/pdf
  _desktop_mime_viewer thunar.desktop inode/directory
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

# _desktop_effects: SwayFX (AUR; it replaces sway) when EFFECTS=yes, stock sway otherwise. A failed SwayFX
# build leaves stock sway with a warning. ultron update sets _DESKTOP_FX_AFTER_AUR=1 so its root steps skip
# the build (they hold the sudo ticket), then calls this again after its AUR phase.
_desktop_effects() {
  local fx
  conf_var fx EFFECTS
  if [[ "$fx" == yes ]]; then
    if pacman -Q swayfx >/dev/null 2>&1 || [[ "${_DESKTOP_FX_AFTER_AUR:-0}" == 1 ]]; then return 0; fi
    say "Installing SwayFX (sway with rounded corners, shadows and animations, built from the AUR)"
    if yay -S --needed --noconfirm --ask 4 swayfx; then
      say "SwayFX is installed: log out and in (Super+Escape, Log out) to start the effects"
    else
      warn "Effects are off: SwayFX didn't build; ultron update tries again."
    fi
  elif pacman -Q swayfx >/dev/null 2>&1; then
    say "EFFECTS=$fx: replacing SwayFX with stock sway (from your next login)"
    sudo pacman -S --noconfirm --ask 4 sway || die "Couldn't replace SwayFX with sway (see above); rerun: ultron install desktop"
  fi
}

# _desktop_first_boot_done: remove the first-boot autologin and install-on-login that bootstrap.sh armed.
# The last root action of this step (the last root step of a default install): the install's root work is
# done, so tty1 goes back to a normal login.
_desktop_first_boot_done() {
  local files=(/var/lib/ultron/firstboot /etc/systemd/system/getty@tty1.service.d/ultron-firstboot.conf
    /etc/profile.d/ultron-firstboot.sh) f
  for f in "${files[@]}"; do
    if [[ -e "$f" ]]; then
      say "Removing the first-boot autologin"
      sudo rm -f "${files[@]}"
      sudo systemctl daemon-reload
      return 0
    fi
  done
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

  _desktop_effects
  say "Writing the theme and settings into the app configs"
  # shellcheck source=../cmd/apply.sh
  source "$ULTRON_ROOT/lib/cmd/apply.sh"
  cmd_apply --no-reload

  _desktop_keyring
  xdg-user-dirs-update
  mkdir -p "$HOME/Pictures/Screenshots"
  _desktop_mime
  _desktop_shell
  _desktop_first_boot_done # keep last: see its comment
}
