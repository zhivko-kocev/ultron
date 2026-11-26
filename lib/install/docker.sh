# shellcheck shell=bash
# step docker: rootless Docker for the user (no docker group).

step_docker() {
  say "Starting rootless Docker (user docker.socket)"
  systemctl --user enable --now docker.socket || die "Couldn't start the user docker.socket (is docker-rootless-extras installed?)"
  export DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}
  local opts
  if ! opts=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null); then
    # Rootless Docker loads kernel modules of the running kernel; an upgrade in this run removed them.
    if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
      warn "The kernel was upgraded, so rootless Docker can't start until you reboot: reboot, then run ultron update again"
      return 0
    fi
    die "docker info failed (journalctl --user -u docker). If the docker and docker-rootless-extras versions differ, rebuild docker-rootless-extras for the installed docker version."
  fi
  [[ "$opts" == *rootless* ]] || die "Docker isn't running rootless (security options: $opts)."
  if id -nG "$ULTRON_USER" | tr ' ' '\n' | grep -qx docker; then
    die "$ULTRON_USER is in the docker group (root-equivalent): remove it with sudo gpasswd -d $ULTRON_USER docker"
  fi
  ok "Docker is rootless and you're not in the docker group"
}
