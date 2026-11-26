# shellcheck shell=bash
# ultron doctor [--root] [--deep]: check the whole system; exit 1 on any FAIL.
# No sudo by default, so agents can run it without a password popup. --root adds the checks that need
# root (boot menu, snapshots); --deep implies --root and also asks the local model.

# shellcheck source=install.sh
source "$ULTRON_ROOT/lib/cmd/install.sh"

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
  n=$({ sudo snapper -c root --csvout list --columns number 2>/dev/null || true; } | awk -F, 'NR > 1 && $1 > 0' | wc -l)
  ((n >= 1))
}

# _check_links: every file of ultron's own home/* packages appears in ~ as a link into the checkout.
_check_links() {
  local ur rel real bad=() total=0 d f
  ur=$(readlink -f "$ULTRON_ROOT")
  for d in "$ur"/home/*/; do
    while IFS= read -r -d '' f; do
      rel=${f#"$d"}
      total=$((total + 1))
      real=$(readlink -f "$HOME/$rel" 2>/dev/null || true)
      if [[ -z "$real" || ! -e "$real" || "$real" != "$ur/"* ]]; then bad+=("$rel"); fi
    done < <(find "$d" -type f ! -name '.stow-local-ignore' -print0)
  done
  if ((${#bad[@]} == 0)); then
    _pass "stow links: all $total resolve into $ur"
  else
    _fail "stow links: ${#bad[@]} of $total don't resolve into $ur (rerun ultron install desktop): ${bad[*]:0:10}"
  fi
}

_check_generated() {
  local f missing=()
  for f in "$ULTRON_GEN"/{sway.conf,effects.conf,foot.ini,fuzzel.ini,colors,swayidle} "$HOME/.config/mako/config" "$HOME/.config/swaylock/config"; do
    [[ -s "$f" ]] || missing+=("${f/#"$HOME"/\~}")
  done
  if ((${#missing[@]} == 0)); then
    _pass "generated config files exist"
  else
    _fail "generated config files missing (run ultron apply): ${missing[*]}"
  fi
}

# _check_effects: EFFECTS=yes needs SwayFX (stock sway is the fallback when it didn't build).
_check_effects() {
  local fx
  conf_var fx EFFECTS
  if [[ "$fx" != yes ]]; then
    _info "effects are off (EFFECTS=$fx)"
  elif pacman -Q swayfx >/dev/null 2>&1; then
    _pass "effects: SwayFX is installed"
  else
    _warnl "effects: EFFECTS=yes but SwayFX isn't installed (stock sway runs instead): ultron install desktop"
  fi
}

_check_boss() {
  local boss
  boss=$(boss_kind)
  read -r boss _ <<<"$boss"
  if have "$boss"; then _pass "boss command '$boss' exists"; else _fail "boss command '$boss' isn't installed (ultron conf set BOSS omp, or install it)"; fi
}

_check_docker() {
  local opts
  # docker info would start the daemon (socket activation): only ask a running one.
  if systemctl --user is-active -q docker.service; then
    opts=$(DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock} docker info --format '{{.SecurityOptions}}' 2>/dev/null || true)
    if [[ "$opts" == *rootless* ]]; then _pass "Docker is rootless"; else _fail "Docker is rootless (docker info: ${opts:-no answer})"; fi
  else
    _info "Docker isn't running (it starts on first use)"
  fi
  if id -nG "$ULTRON_USER" | tr ' ' '\n' | grep -qx docker; then
    _fail "$ULTRON_USER is in the docker group (root-equivalent): sudo gpasswd -d $ULTRON_USER docker"
  else
    _pass "not in the docker group"
  fi
}

_check_ai() {
  local local_ai model role
  if ! local_ai_on; then
    conf_var local_ai LOCAL_AI
    if [[ "$local_ai" == auto ]]; then
      _info "local AI is off (LOCAL_AI=auto: no graphics card with 4 GB or more)"
    else
      _info "local AI is off (LOCAL_AI=$local_ai)"
    fi
    return 0
  fi
  model=$(ask_model)
  _check "ollama is active" systemctl is-active -q ollama
  if { ollama list 2>/dev/null || true; } | awk 'NR > 1 { print $1 }' | grep -qxF -- "$model"; then
    _pass "$model is pulled"
  else
    _fail "$model is pulled (ultron install ai)"
  fi
  if have omp; then
    role=$(omp config get modelRoles 2>/dev/null | jq -r '.commit // ""' 2>/dev/null || true)
    if [[ "$role" == ollama/* ]]; then
      _pass "omp commit role starts with ollama/"
    else
      _warnl "omp commit role is '${role:-unset}', not ollama/ first (ultron install agents sets it again)"
    fi
  fi
}

_check_idle_inhibitors() {
  # swayidle turns off all its timeouts while any logind idle inhibitor is held (typing guard, away, lock).
  local idle_blockers
  idle_blockers=$({ systemd-inhibit --list --no-pager --no-legend 2>/dev/null || true; } |
    awk '$6 ~ /(^|:)idle(:|$)/ && $NF == "block" { print $5 }' | sort -u | paste -sd, - || true)
  if [[ -z "$idle_blockers" ]]; then
    _pass "no idle inhibitor turns off swayidle"
  else
    _fail "idle inhibitors held by $idle_blockers turn off swayidle (typing guard, away, lock); omp: ultron install agents, then restart the boss"
  fi
}

_check_jocasta() {
  local v pin want
  if [[ ! -e "$HOME/.local/bin/jocasta" ]]; then
    _info "Jocasta isn't set up (optional: ultron install jocasta)"
    return 0
  fi
  if v=$("$HOME/.local/bin/jocasta" --version 2>/dev/null); then
    _pass "jocasta runs: $v"
  else
    _fail "jocasta --version fails (ultron install jocasta)"
  fi
  pin=$(omp_pin)
  want=$(jocasta_omp_want)
  if [[ -n "$want" ]]; then
    if [[ "$pin" == "$want" ]]; then _info "omp pin $pin matches Jocasta"; else _info "omp pin ${pin:-unset} differs from Jocasta's $want (ultron install jocasta)"; fi
  fi
}

_check_net() {
  if ! systemctl is-enabled -q tailscaled 2>/dev/null; then
    _info "Tailscale isn't set up (optional: ultron install net)"
  else
    _check "tailscale status" tailscale status
  fi
  if [[ ! -e "$NTFY_ENV" ]]; then
    _info "phone alerts aren't set up (optional: ultron install ntfy)"
  else
    _check "ntfy /v1/health answers" curl -fsS --max-time 3 http://127.0.0.1:2586/v1/health
  fi
}

# _spec_present SPEC: a block device matches LABEL=x, UUID=x or /dev/x (no root needed).
_spec_present() {
  case $1 in
  /dev/*) [[ -b "$1" ]] ;;
  LABEL=* | UUID=*)
    lsblk -J -o UUID,LABEL 2>/dev/null |
      jq -e --arg k "${1%%=*}" --arg v "${1#*=}" \
        '[.. | objects | select(($k == "UUID" and .uuid == $v) or ($k == "LABEL" and .label == $v))] | length > 0' >/dev/null
    ;;
  *) return 1 ;;
  esac
}

# _check_mounts: MOUNTS entries mounted; any ultron-migration-* copy lying around is a plaintext copy of a home.
_check_mounts() {
  local spec mp roots=() r d
  while read -r -u 3 spec mp; do
    [[ -n "$spec" ]] || continue
    roots+=("$mp")
    if mountpoint -q "$mp"; then
      _pass "$mp is mounted ($spec)"
    elif ! _spec_present "$spec"; then
      _warnl "$mp: no disk matches $spec (not connected?)"
    else
      _fail "$mp isn't mounted ($spec is connected; ultron install system)"
    fi
  done 3< <(conf_mounts)
  for d in /mnt/*/; do
    if [[ -d "$d" ]]; then roots+=("${d%/}"); fi
  done
  ((${#roots[@]})) || return 0
  while IFS= read -r -d '' d; do
    _warnl "$d is a plaintext copy of a home folder: delete it once checked (ultron migrate clean --from ${d%/*})"
  done < <(for r in "${roots[@]}"; do find "$r" -mindepth 1 -maxdepth 1 -type d -name 'ultron-migration-*' -print0 2>/dev/null || true; done | sort -zu)
}

_check_checkout() {
  local changes
  changes=$(git -C "$ULTRON_ROOT" status --porcelain 2>/dev/null || echo "not a git checkout")
  if [[ -z "$changes" ]]; then
    _pass "ultron checkout is clean"
  else
    _warnl "ultron checkout has local changes, so ultron update doesn't pull (updates are paused): git -C $ULTRON_ROOT status"
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
    if { systemctl --user show-environment 2>/dev/null || true; } | grep -q '^WAYLAND_DISPLAY='; then
      _pass "user manager has WAYLAND_DISPLAY"
    else
      _fail "user manager has WAYLAND_DISPLAY"
    fi
  else
    _warnl "ultron-attentiond: not in sway, rerun after reboot"
    _warnl "user manager WAYLAND_DISPLAY: not in sway, rerun after reboot"
  fi
}

_check_root() {
  sudo -v || die "--root needs sudo."
  _check "/boot/limine.conf has a kernel entry" sudo grep -qE "$LIMINE_KERNEL_RE" /boot/limine.conf
  _check "snapper has at least one snapshot of /" _snapper_has_entries
}

_check_deep() {
  local out
  if ! local_ai_on; then
    _info "--deep: local AI is off, nothing to ask"
    return 0
  fi
  out=$(timeout 120 ask "say ok" 2>/dev/null || true)
  if [[ -n "$out" ]]; then _pass "ask \"say ok\" answered"; else _fail "ask \"say ok\" answered"; fi
  if { ollama ps 2>/dev/null || true; } | grep -q '100% GPU'; then
    _pass "ollama runs 100% on the GPU"
  elif is_vm; then
    _warnl "ollama isn't 100% GPU (VM: CPU is expected)"
  else
    _warnl "ollama doesn't run 100% on the GPU ($({ ollama ps 2>/dev/null || true; } | sed -n 2p)); see OLLAMA_GPU"
  fi
}

cmd_doctor() {
  local root=0 deep=0 a
  for a in "$@"; do
    case $a in
    --root) root=1 ;;
    --deep) root=1 deep=1 ;;
    *) die "usage: ultron doctor [--root] [--deep]" ;;
    esac
  done

  _check "UEFI boot" is_uefi
  _check "root is on LUKS" _root_on_luks
  _check "limine-snapper-sync.service is enabled" systemctl is-enabled -q limine-snapper-sync.service
  _check "greetd autologin names $ULTRON_USER" _greetd_autologin
  _check "askpass is root-owned and wired into sudo.conf" _askpass_ok
  _check "ufw is active" systemctl is-active -q ufw
  _check_links
  _check_generated
  _check_effects
  _check_boss
  _check_docker
  _check_ai
  _check_idle_inhibitors
  _check_jocasta
  _check_net
  _check_mounts
  _check_checkout
  _check_disk
  _check_session
  if ((root)); then
    _check_root
  else
    _info "boot menu and snapshot checks need root: ultron doctor --root (--deep also asks the local model)"
  fi
  if ((deep)); then _check_deep; fi

  echo
  if ((_D_FAILS)); then
    printf '%d FAIL, %d WARN\n' "$_D_FAILS" "$_D_WARNS"
    return 1
  fi
  printf 'All checks passed (%d WARN)\n' "$_D_WARNS"
}
