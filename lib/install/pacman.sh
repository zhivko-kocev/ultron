# shellcheck shell=bash
# step pacman: colour output and 8 parallel downloads in /etc/pacman.conf.

step_pacman() {
  say "Turning on Color and ParallelDownloads = 8 in /etc/pacman.conf"
  sudo sed -i -E \
    -e 's/^#[[:space:]]*Color[[:space:]]*$/Color/' \
    -e 's/^#?[[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 8/' \
    /etc/pacman.conf
  if ! grep -q '^ParallelDownloads = 8' /etc/pacman.conf; then
    sudo sed -i -E 's/^\[options\]$/[options]\nParallelDownloads = 8/' /etc/pacman.conf
  fi
  if ! grep -q '^Color' /etc/pacman.conf; then
    sudo sed -i -E 's/^\[options\]$/[options]\nColor/' /etc/pacman.conf
  fi
}
