# shellcheck shell=bash
# step docker: rootless Docker for the user (no docker group).

step_docker() {
  say "Starting rootless Docker (user docker.socket)"
  systemctl --user enable --now docker.socket || die "Couldn't start the user docker.socket (is docker-rootless-extras installed?)"
  export DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}
  local opts
  opts=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null) ||
    die "docker info failed. If docker-rootless-extras and docker versions differ, see docs/migrate.md."
  [[ "$opts" == *rootless* ]] || die "Docker isn't running rootless (security options: $opts)."
  if id -nG | tr ' ' '\n' | grep -qx docker; then
    die "$ULTRON_USER is in the docker group (root-equivalent): remove it with sudo gpasswd -d $ULTRON_USER docker"
  fi
  ok "Docker is rootless and you're not in the docker group"
}
