# shellcheck shell=bash
# ultron doctor [--deep]: check the whole system; exit 1 on any FAIL.

_D_FAILS=0 _D_WARNS=0

_pass() { printf '%sPASS%s %s\n' "$_c_ok" "$_c_off" "$*"; }
_fail() {
  printf '%sFAIL%s %s\n' "$_c_err" "$_c_off" "$*"
  _D_FAILS=$((_D_FAILS + 1))
}
_warnl() {
  printf '%sWARN%s %s\n' "$_c_warn" "$_c_off" "$*"
  _D_WARNS=$((_D_WARNS + 1))
}
_info() { printf 'INFO %s\n' "$*"; }

# _check DESC CMD...: PASS when CMD succeeds, else FAIL.
_check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc"; fi
}

# _vm_soft DESC CMD...: like _check, but WARN instead of FAIL inside a VM.
_vm_soft() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    _pass "$desc"
  elif is_vm; then
    _warnl "$desc (VM)"
  else
    _fail "$desc"
  fi
}

_root_on_luks() {
  local src
  src=$(findmnt -no SOURCE /)
  src=${src%%\[*}
  lsblk -s -no TYPE "$src" | grep -qx crypt
}

_greetd_autologin() {
  awk -v u="$ULTRON_USER" '
    /^[[:space:]]*\[/ { sec = $0; next }
    sec ~ /^[[:space:]]*\[initial_session\]/ && $0 ~ "^[[:space:]]*user[[:space:]]*=[[:space:]]*\"" u "\"" { f = 1 }
    END { exit !f }' /etc/greetd/config.toml
}

_askpass_ok() {
  [[ -x /usr/lib/ultron/askpass && "$(stat -c %U /usr/lib/ultron/askpass)" == root ]] &&
    grep -qE '^[[:space:]]*Path[[:space:]]+askpass[[:space:]]+/usr/lib/ultron/askpass' /etc/sudo.conf
}

_snapper_has_entries() {
  local n
  n=$(sudo snapper -c root --csvout list --columns number 2>/dev/null | awk -F, 'NR > 1 && $1 > 0' | wc -l)
  ((n >= 1))
}

# _expected_links REPO PACKAGE...: home-relative paths every package file should appear at.
_expected_links() {
  local repo=$1 pkg f
  shift
  for pkg in "$@"; do
    [[ -d "$repo/$pkg" ]] || continue
    while IFS= read -r -d '' f; do
      printf '%s\n' "${f#"$repo/$pkg/"}"
    done < <(find "$repo/$pkg" -type f ! -name '.stow-local-ignore' ! -path '*/.git/*' -print0)
  done
}

_check_links() {
  local ur dr rel real bad=() total=0 pkgs=() d
  ur=$(readlink -f "$HOME/Projects/ultron")
  dr=$(readlink -f "$HOME/Projects/dotfiles" 2>/dev/null || printf '%s' "$HOME/Projects/dotfiles")
  for d in "$ur"/home/*/; do
    d=${d%/}
    pkgs+=("${d##*/}")
  done
  local list
  list=$(_expected_links "$ur/home" "${pkgs[@]}")
  if [[ -d "$dr" ]]; then list+=$'\n'$(_expected_links "$dr" zsh git mise agents zed); fi
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    total=$((total + 1))
    real=$(readlink -f "$HOME/$rel" 2>/dev/null || true)
    if [[ -z "$real" || ! -e "$real" ]] || [[ "$real" != "$ur/"* && "$real" != "$dr/"* ]]; then
      bad+=("$rel")
    fi
  done <<<"$list"
  if ((${#bad[@]} == 0)); then
    _pass "stow links: all $total resolve into the repos"
  else
    _fail "stow links: ${#bad[@]} of $total don't resolve into the repos (rerun ultron install desktop dotfiles): ${bad[*]:0:10}"
  fi
}

_check_docker() {
  local opts
  opts=$(DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock} docker info --format '{{.SecurityOptions}}' 2>/dev/null || true)
  if [[ "$opts" == *rootless* ]]; then _pass "Docker is rootless"; else _fail "Docker is rootless (docker info: ${opts:-no answer})"; fi
  if id -nG | tr ' ' '\n' | grep -qx docker; then
    _fail "$ULTRON_USER is in the docker group"
  else
    _pass "not in the docker group"
  fi
}

_check_ai() {
  _check "ollama is active" systemctl is-active -q ollama
  if ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qx 'qwen3:4b'; then
    _pass "qwen3:4b is pulled"
  else
    _fail "qwen3:4b is pulled (ultron install ai)"
  fi
  local role
  role=$(omp config get modelRoles.commit 2>/dev/null | head -n1 | tr -d "\"'[:space:]" || true)
  if [[ "$role" == ollama/* ]]; then
    _pass "omp commit role starts with ollama/"
  else
    _warnl "omp commit role is '${role:-unset}', not ollama/ first (ultron install ai sets it again)"
  fi
}

_check_jocasta() {
  local v pin want
  if v=$(jocasta --version 2>/dev/null); then
    _info "jocasta: $v"
  else
    _info "jocasta isn't installed (ultron install jocasta)"
  fi
  pin=$(sed -n -E 's/^[[:space:]]*oh-my-pi[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' /etc/mise/conf.d/ultron-tools.toml 2>/dev/null | head -n1)
  want=$(grep -oE 'checked against omp [0-9]+(\.[0-9]+)*' "$JOCASTA_DIR/README.md" 2>/dev/null | head -n1 | grep -oE '[0-9]+(\.[0-9]+)*$' || true)
  if [[ -n "$want" ]]; then
    if [[ "$pin" == "$want" ]]; then _info "omp pin $pin matches Jocasta"; else _info "omp pin ${pin:-unset} differs from Jocasta's $want (ultron install jocasta)"; fi
  fi
}

_check_net() {
  if is_vm; then
    if tailscale status >/dev/null 2>&1; then _pass "tailscale status"; else _warnl "tailscale status (VM)"; fi
  elif ! systemctl is-enabled -q tailscaled 2>/dev/null; then
    _warnl "Tailscale isn't set up yet (ultron install net)"
  else
    _check "tailscale status" tailscale status
  fi
  if [[ ! -e "$NTFY_ENV" ]] && ! is_vm; then
    _warnl "ntfy isn't set up yet (ultron install ntfy)"
  else
    _vm_soft "ntfy /v1/health answers" curl -fsS --max-time 3 http://127.0.0.1:2586/v1/health
  fi
}

_check_gpu() {
  local cards
  cards=$(find /sys/class/drm -maxdepth 1 -name 'card[0-9]' | wc -l)
  if sudo dmesg 2>/dev/null | grep -qi 'Fatal error during GPU init'; then
    _info "amdgpu reported 'Fatal error during GPU init' (iGPU down; CSM on?)"
  fi
  if ((cards >= 2)); then
    _info "GPUs: $cards cards in /sys/class/drm (iGPU up)"
  elif is_vm; then
    _warnl "GPUs: $cards card (VM)"
  else
    _info "GPUs: only $cards card in /sys/class/drm (the iGPU isn't up)"
  fi
}

_check_disk() {
  local used
  used=$(df --output=pcent / | tail -n1 | tr -dc '0-9')
  if ((100 - used >= 10)); then _pass "disk: $((100 - used)) % free on /"; else _fail "disk: only $((100 - used)) % free on /"; fi
}

_check_session() {
  if [[ -n "${SWAYSOCK:-}" ]]; then
    _check "ultron-attentiond is active" systemctl --user is-active -q ultron-attentiond
    if systemctl --user show-environment 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; then
      _pass "user manager has WAYLAND_DISPLAY"
    else
      _fail "user manager has WAYLAND_DISPLAY"
    fi
  else
    _warnl "ultron-attentiond: not in sway, rerun after reboot"
    _warnl "user manager WAYLAND_DISPLAY: not in sway, rerun after reboot"
  fi
}

_check_deep() {
  local out
  out=$(timeout 120 ask "say ok" 2>/dev/null || true)
  if [[ -n "$out" ]]; then _pass "ask \"say ok\" answered"; else _fail "ask \"say ok\" answered"; fi
  if ollama ps 2>/dev/null | grep -q '100% GPU'; then
    _pass "ollama runs 100% on the GPU"
  elif is_vm; then
    _warnl "ollama isn't 100% GPU (VM: CPU is expected)"
  else
    _fail "ollama runs 100% on the GPU ($(ollama ps 2>/dev/null | tail -n +2 | head -n1))"
  fi
}

cmd_doctor() {
  local deep=0
  case ${1:-} in
  --deep) deep=1 ;;
  "") ;;
  *) die "usage: ultron doctor [--deep]" ;;
  esac
  sudo -v || die "doctor needs sudo for some checks."

  _check "UEFI boot" is_uefi
  _check "root is on LUKS" _root_on_luks
  _check "/boot/limine.conf has kernel_path" sudo grep -q kernel_path /boot/limine.conf
  _check "limine-snapper-sync.service is enabled" systemctl is-enabled -q limine-snapper-sync.service
  _check "snapper has at least one snapshot of /" _snapper_has_entries
  _check "greetd autologin names $ULTRON_USER" _greetd_autologin
  _check "askpass is root-owned and wired into sudo.conf" _askpass_ok
  _check_links
  _check_docker
  _check_ai
  _check_jocasta
  _check_net
  _check "ufw is active" sh -c 'sudo ufw status | grep -q "Status: active"'
  if is_vm; then
    _warnl "$SSD_MOUNT: skipped (VM)"
  else
    _check "$SSD_MOUNT is mounted" mountpoint -q "$SSD_MOUNT"
  fi
  _check_gpu
  _check_disk
  _check_session
  if ((deep)); then _check_deep; fi

  echo
  if ((_D_FAILS)); then
    printf '%d FAIL, %d WARN\n' "$_D_FAILS" "$_D_WARNS"
    return 1
  fi
  printf 'All checks passed (%d WARN)\n' "$_D_WARNS"
}
