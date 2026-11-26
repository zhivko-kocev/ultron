# shellcheck shell=bash
# ultron migrate backup --to DEST [--exclude PATTERN]... : copy home, /etc and Docker volumes to another disk.
# ultron migrate restore --from SRC [--dry-run]          : bring that copy back into this home.
# ultron migrate clean --from SRC                        : delete the copies once you've checked the restore.
# DEST/SRC is a folder, or a device (LABEL=x, UUID=x, /dev/x) that is mounted for the run when it isn't already.

# shellcheck source=install.sh
source "$ULTRON_ROOT/lib/cmd/install.sh"

MIGRATE_MNT=/mnt/ultron-migrate

# Static backup excludes (rsync patterns anchored at the home folder). Rootless Docker's data folder is
# skipped: images are pulled again and volumes are exported to docker-volumes/.
MIGRATE_BACKUP_EXCLUDES=(
  /.cache/ /.local/share/mise/ /.local/share/Trash/ /.local/share/ultron-vm/ /.local/share/docker/
  /.stremio-server/ /.rustup/ /.cargo/registry/ /.cargo/git/ /.npm/_cacache/ /.bun/install/cache/
  "/Downloads/archlinux-*.iso"
)

# Static restore excludes: an Omarchy desktop, files ultron and dotfiles own, the default checkout paths.
MIGRATE_RESTORE_EXCLUDES=(
  /.config/hypr/ /.config/omarchy/ /.local/share/omarchy/ /.local/state/omarchy/ /.config/uwsm/
  /.config/waybar/ /.config/walker/ /.config/elephant/ /.config/quickshell/ /.config/alacritty/
  /.config/ghostty/ /.config/kitty/ /.config/swayosd/ /.config/mako/ /.config/starship.toml
  /.config/xdg-desktop-portal/ /.config/fontconfig/ /.config/mimeapps.list /.config/systemd/
  /.config/environment.d/ /.config/herdr/ /.local/state/herdr/ /.local/share/herdr/ /.config/mise/
  /.local/state/mise/ /.local/share/applications/ /.agents/ /.bashrc /.bash_profile /.bash_logout
  /.profile /.XCompose /.zshrc /.zshenv /.config/chrome-flags.conf /.config/chromium-flags.conf
  /.config/zed/ /.config/git/ /Projects/ultron/ /Projects/dotfiles/ /.local/share/docker/
)

_MIG_MOUNTED=""

_migrate_usage() {
  cat >&2 <<'EOF'
usage: ultron migrate backup --to DEST [--exclude PATTERN]...
       ultron migrate restore --from SRC [--dry-run]
       ultron migrate clean --from SRC
DEST/SRC: a folder, or a disk as LABEL=x, UUID=x or /dev/x (mounted for the run).
To find your disks: lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINTS
EOF
  exit 1
}

_migrate_umount() {
  [[ -n "$_MIG_MOUNTED" ]] || return 0
  sync
  if sudo umount "$_MIG_MOUNTED"; then
    ok "Unmounted $_MIG_MOUNTED"
  else
    warn "Couldn't unmount $_MIG_MOUNTED: run sudo umount $_MIG_MOUNTED"
  fi
  _MIG_MOUNTED=""
}

# _migrate_open SPEC: sets MIG_BASE, the folder for SPEC. A device that isn't mounted is mounted at
# /mnt/ultron-migrate and unmounted again when the command ends (however it ends).
_migrate_open() {
  local spec=$1 mp
  trap '_migrate_umount; sudo_drop' EXIT
  case $spec in
  LABEL=* | UUID=* | /dev/*)
    mp=$(findmnt -n -o TARGET -S "$spec" 2>/dev/null | head -n1 || true)
    if [[ -n "$mp" ]]; then
      echo "Using $spec, mounted at $mp"
    else
      say "Mounting $spec at $MIGRATE_MNT for this run"
      sudo mkdir -p "$MIGRATE_MNT"
      sudo mount "$spec" "$MIGRATE_MNT" ||
        die "Couldn't mount $spec. Is it connected? Check with: lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINTS"
      _MIG_MOUNTED=$MIGRATE_MNT
      mp=$MIGRATE_MNT
    fi
    MIG_BASE=$mp
    ;;
  *)
    [[ -d "$spec" ]] || die "$spec isn't a folder or a disk (LABEL=x, UUID=x, /dev/x). Check with: lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINTS"
    MIG_BASE=$(readlink -f "$spec")
    ;;
  esac
}

_migrate_refuse_running() {
  local p running=()
  for p in "$@"; do
    if pgrep -x "$p" >/dev/null 2>&1; then running+=("$p"); fi
  done
  ((${#running[@]} == 0)) || die "Close these first (they change files while they run): ${running[*]}"
}

# _migrate_build_dirs: Rust target/ next to Cargo.toml and node_modules/ next to package.json
# under ~/Projects and ~/Work, as rsync patterns anchored at home.
_migrate_build_dirs() {
  local roots=() r d
  for r in "$HOME/Projects" "$HOME/Work"; do
    if [[ -d "$r" ]]; then roots+=("$r"); fi
  done
  ((${#roots[@]})) || return 0
  while IFS= read -r -d '' d; do
    case ${d##*/} in
    target) [[ -f "${d%/*}/Cargo.toml" ]] || continue ;;
    node_modules) [[ -f "${d%/*}/package.json" ]] || continue ;;
    esac
    printf '/%s/\n' "${d#"$HOME/"}"
  done < <(find "${roots[@]}" -type d \( -name target -o -name node_modules \) -prune -print0 2>/dev/null || true)
}

# _migrate_transfer_bytes RSYNC_ARGS...: "Total transferred file size" of a dry run (empty when it fails).
_migrate_transfer_bytes() {
  { sudo rsync -aHAX --dry-run --mkpath --stats "$@" 2>/dev/null || true; } |
    sed -n -E 's/^Total transferred file size: ([0-9,]+).*/\1/p' | tr -d ,
}

# _migrate_docker_cmd: sets MIG_DOCKER to the docker command that reaches this machine's daemon
# (rootless as you, else rootful through sudo); empty when no daemon answers.
_migrate_docker_cmd() {
  MIG_DOCKER=()
  have docker || return 0
  if DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock} docker info >/dev/null 2>&1; then
    MIG_DOCKER=(env "DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}" docker)
  elif sudo docker info >/dev/null 2>&1; then
    MIG_DOCKER=(sudo docker)
  fi
}

_migrate_backup() {
  local to="" extra=()
  while (($#)); do
    case $1 in
    --to)
      [[ -n "${2:-}" ]] || _migrate_usage
      to=$2
      shift 2
      ;;
    --exclude)
      [[ -n "${2:-}" ]] || die "--exclude needs a pattern, like --exclude /Downloads/"
      extra+=("$2")
      shift 2
      ;;
    *) _migrate_usage ;;
    esac
  done
  [[ -n "$to" ]] || _migrate_usage
  ((EUID != 0)) || die "Run this as your user, not root."
  local browser
  read -r browser _ <<<"$(browser_cmd)"
  _migrate_refuse_running omp chrome chromium firefox jocasta "${browser##*/}"
  sudo_keepalive
  _migrate_open "$to"
  local base=$MIG_BASE home
  home=$(readlink -f "$HOME")
  [[ "$base" != "$home" && "$base" != "$home"/* ]] || die "$base is inside your home folder: the copy would copy itself. Pick another disk."
  ls -la "$base"
  df -h "$base"

  local dest
  dest=$base/ultron-migration-$(date +%F)
  if [[ -e "$dest" ]]; then dest+=-$(date +%H%M); fi
  [[ ! -e "$dest" ]] || die "$dest already exists; wait a minute and run this again."

  local list
  list=$(mktemp)
  {
    printf '%s\n' "${MIGRATE_BACKUP_EXCLUDES[@]}"
    if ((${#extra[@]})); then printf '%s\n' "${extra[@]}"; fi
    _migrate_build_dirs
  } >"$list"
  say "Excluding $(wc -l <"$list") patterns (caches, build folders, the VM, ISOs)"

  _migrate_docker_cmd
  local v vols=() vol_bytes=0 mp b
  if ((${#MIG_DOCKER[@]})); then
    mapfile -t vols < <("${MIG_DOCKER[@]}" volume ls -q 2>/dev/null || true)
    for v in "${vols[@]}"; do
      mp=$("${MIG_DOCKER[@]}" volume inspect -f '{{.Mountpoint}}' "$v" 2>/dev/null || true)
      b=$({ sudo du -sb "$mp" 2>/dev/null || true; } | cut -f1)
      vol_bytes=$((vol_bytes + ${b:-0}))
    done
  fi

  # Space check: dry-run size (plus the Docker volumes, before compression) x 1.1 must fit.
  say "Measuring what will be copied (dry run)"
  local need_home need_etc need avail
  need_home=$(_migrate_transfer_bytes --exclude-from="$list" "$HOME/" "$dest/home/")
  need_etc=$(_migrate_transfer_bytes /etc/ "$dest/etc/")
  [[ -n "$need_home" ]] || die "The rsync dry run failed; run it by hand to see why: sudo rsync -aHAX --dry-run --stats --exclude-from=$list ~/ $dest/home/"
  need=$(((need_home + ${need_etc:-0} + vol_bytes) * 11 / 10))
  avail=$(df --output=avail -B1 "$base" | tail -n1 | tr -dc '0-9')
  echo "Needs about $(numfmt --to=iec "$need") (with 10 % margin; Docker volumes: $(numfmt --to=iec "$vol_bytes")); free: $(numfmt --to=iec "$avail")"
  if ((need > avail)); then
    rm -f "$list"
    die "Not enough space on $base. Run again with --exclude /Downloads/ (and copy Downloads to another disk)."
  fi

  sudo mkdir -p "$dest/home" "$dest/etc"
  # A rootless daemon's containers write as you, so the volume folder must be yours.
  sudo install -d -o "$ULTRON_USER" -m 0755 "$dest/docker-volumes"

  if ((${#vols[@]})); then
    say "Exporting ${#vols[@]} Docker volumes"
    for v in "${vols[@]}"; do
      echo "  $v"
      "${MIG_DOCKER[@]}" run --rm -v "$v:/v:ro" -v "$dest/docker-volumes:/b" alpine tar -czf "/b/$v.tgz" -C /v . ||
        die "Exporting Docker volume $v failed."
    done
  elif ((${#MIG_DOCKER[@]} == 0)); then
    warn "Docker isn't running: no volumes exported"
  fi

  say "Copying home to $dest/home/"
  sudo rsync -aHAX --info=progress2 --exclude-from="$list" "$HOME/" "$dest/home/" ||
    die "Copying home failed (see above). The partial copy is in $dest (no COMPLETE marker, so restore skips it)."

  say "Copying /etc and the package lists"
  sudo rsync -aHAX /etc/ "$dest/etc/" || die "Copying /etc failed."
  local tmp
  tmp=$(mktemp)
  pacman -Qqe >"$tmp" && sudo install -m 0644 "$tmp" "$dest/pacman-Qqe.txt"
  pacman -Qqm >"$tmp" || true
  sudo install -m 0644 "$tmp" "$dest/pacman-Qqm.txt"
  crontab -l >"$tmp" 2>/dev/null || : >"$tmp"
  sudo install -m 0644 "$tmp" "$dest/crontab.txt"

  # The copy must be complete: a second dry run shows no changes.
  say "Checking the copy (second dry run)"
  local changes
  if ! changes=$(sudo rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$HOME/" "$dest/home/"); then
    die "The check run of rsync failed (see above); the copy in $dest isn't marked complete."
  fi
  if [[ -n "$changes" ]]; then
    warn "Files changed during the copy; copying them again:"
    head -n 20 <<<"$changes" >&2
    sudo rsync -aHAX --exclude-from="$list" "$HOME/" "$dest/home/" || die "Copying the changed files failed (see above)."
    if ! changes=$(sudo rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$HOME/" "$dest/home/"); then
      die "The check run of rsync failed (see above); the copy in $dest isn't marked complete."
    fi
    if [[ -n "$changes" ]]; then
      head -n 20 <<<"$changes" >&2
      rm -f "$list" "$tmp"
      die "Files keep changing in your home (above). Close the programs that write them, then run ultron migrate backup again."
    fi
  fi
  rm -f "$list"

  date -u +%FT%TZ >"$tmp"
  sudo install -m 0644 "$tmp" "$dest/COMPLETE"
  rm -f "$tmp"
  sync
  local size
  size=$({ sudo du -sh "$dest" || true; } | cut -f1)
  ok "Backup done: $dest (${size:-size unknown})"
  echo "It's a plaintext copy of your home: once the restore is checked, delete it with ultron migrate clean --from $to"
  _migrate_umount
}

# _migrate_pick BASE: the copy to restore from. BASE may be a copy itself; otherwise the newest complete one in it.
_migrate_pick() {
  local base=$1 d newest="" newer=()
  if [[ -d "$base/home" ]]; then
    [[ -e "$base/COMPLETE" ]] || warn "$base has no COMPLETE marker: its backup may not have finished"
    printf '%s\n' "$base"
    return 0
  fi
  while IFS= read -r d; do
    if [[ -e "$d/COMPLETE" ]]; then
      newest=$d
      newer=()
    else
      newer+=("$d")
    fi
  done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -name 'ultron-migration-*' 2>/dev/null | sort)
  if [[ -z "$newest" ]]; then
    ((${#newer[@]} == 0)) || die "No complete ultron-migration-* copy in $base (unfinished: ${newer[*]}). To use one anyway, pass it: --from <that folder>"
    die "No ultron-migration-* folder in $base."
  fi
  if ((${#newer[@]})); then warn "Skipping newer copies that didn't finish: ${newer[*]}"; fi
  printf '%s\n' "$newest"
}

_migrate_restore() {
  local from="" dry=0
  while (($#)); do
    case $1 in
    --from)
      [[ -n "${2:-}" ]] || _migrate_usage
      from=$2
      shift 2
      ;;
    --dry-run)
      dry=1
      shift
      ;;
    *) _migrate_usage ;;
    esac
  done
  [[ -n "$from" ]] || _migrate_usage
  ((EUID != 0)) || die "Run this as your user, not root."
  local browser
  read -r browser _ <<<"$(browser_cmd)"
  _migrate_refuse_running chrome chromium firefox "${browser##*/}"
  _migrate_open "$from"

  local dir
  dir=$(_migrate_pick "$MIG_BASE")
  [[ -d "$dir/home" ]] || die "$dir has no home/ folder: is it an ultron migration copy?"
  say "Restoring from $dir"

  # Excludes: every link in ~ that points into the checkouts (stow links), the checkouts themselves,
  # then the static list.
  local ur dr list l real n_links=0
  ur=$(readlink -f "$ULTRON_ROOT")
  dr=$(readlink -f "$DOTFILES_DIR" 2>/dev/null || printf '%s' "$DOTFILES_DIR")
  list=$(mktemp)
  while IFS= read -r -d '' l; do
    real=$(readlink -f "$l" 2>/dev/null || true)
    if [[ "$real" == "$ur" || "$real" == "$ur/"* || "$real" == "$dr" || "$real" == "$dr/"* ]]; then
      printf '/%s\n' "${l#"$HOME/"}" >>"$list"
      n_links=$((n_links + 1))
    fi
  # 2>/dev/null: rootless Docker keeps folders the user can't read (its overlay work dirs); no stow link is there.
  done < <(find "$HOME" -xdev \( -path "$ur" -o -path "$dr" \) -prune -o -type l -print0 2>/dev/null || true)
  local p
  for p in "$ULTRON_ROOT" "$DOTFILES_DIR"; do
    if [[ "$p" == "$HOME"/* ]]; then printf '/%s/\n' "${p#"$HOME/"}" >>"$list"; fi
  done
  printf '%s\n' "${MIGRATE_RESTORE_EXCLUDES[@]}" >>"$list"
  echo "Skipping $n_links linked files, the ultron and dotfiles checkouts, and ${#MIGRATE_RESTORE_EXCLUDES[@]} desktop paths"

  # Plain rsync as the user, not sudo: the backup kept your uid's ownership, so every file you owned is
  # readable here, and nothing root-owned can land in ~. -o/-g are ignored for a non-root rsync, so restored
  # files belong to you. Unreadable files are reported (exit 23).
  if ((dry)); then
    local preview
    preview=$(mktemp -t ultron-restore-preview.XXXXXX)
    rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$dir/home/" "$HOME/" >"$preview" ||
      warn "rsync reported problems (see above)"
    local count
    count=$(grep -c . "$preview" || true)
    say "Dry run: $count changes (full list: $preview). By top-level folder:"
    cut -d' ' -f2- "$preview" | awk -F/ 'NF { print $1 }' | sort | uniq -c | sort -rn | head -n 25 || true
    local tgz
    for tgz in "$dir"/docker-volumes/*.tgz; do
      if [[ -e "$tgz" ]]; then echo "  docker volume: $(basename "$tgz" .tgz)"; fi
    done
    rm -f "$list"
    ok "Nothing was changed. Run without --dry-run to restore."
    _migrate_umount
    return 0
  fi

  say "Copying $dir/home/ into ~ (no deletions)"
  local rc=0
  rsync -aHAX --info=progress2 --exclude-from="$list" "$dir/home/" "$HOME/" || rc=$?
  rm -f "$list"
  case $rc in
  0) ok "Home restored" ;;
  23 | 24) warn "Some files couldn't be read or vanished (rsync exit $rc); the rest is restored" ;;
  *) die "rsync failed (exit $rc)" ;;
  esac

  local tgz v
  export DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}
  for tgz in "$dir"/docker-volumes/*.tgz; do
    [[ -e "$tgz" ]] || continue
    v=$(basename "$tgz" .tgz)
    say "Importing Docker volume $v (rootless)"
    docker volume create "$v" >/dev/null || die "Couldn't create Docker volume $v (is rootless Docker running? ultron install docker)"
    docker run --rm -v "$v:/v" -v "$dir/docker-volumes:/b:ro" alpine tar -xzf "/b/$v.tgz" -C /v ||
      die "Importing Docker volume $v failed."
  done

  xdg-user-dirs-update
  # The restored omp config lacks ultron's settings (its idle inhibitor would turn off the typing guard,
  # away alerts and auto-lock).
  set_omp_settings
  _migrate_umount
  ok "Restore done. Check your files, run ultron doctor, then delete the copy: ultron migrate clean --from $from"
}

_migrate_clean() {
  local from=""
  while (($#)); do
    case $1 in
    --from)
      [[ -n "${2:-}" ]] || _migrate_usage
      from=$2
      shift 2
      ;;
    *) _migrate_usage ;;
    esac
  done
  [[ -n "$from" ]] || _migrate_usage
  ((EUID != 0)) || die "Run this as your user, not root."
  sudo_keepalive
  _migrate_open "$from"
  local base=$MIG_BASE dirs=() d answer
  if [[ "${base##*/}" == ultron-migration-* ]]; then
    dirs=("$base")
  else
    mapfile -t dirs < <(find "$base" -mindepth 1 -maxdepth 1 -type d -name 'ultron-migration-*' 2>/dev/null | sort || true)
  fi
  if ((${#dirs[@]} == 0)); then
    ok "No ultron-migration-* folders in $base"
    _migrate_umount
    return 0
  fi
  echo "Copies in $base:"
  for d in "${dirs[@]}"; do
    printf '  %8s  %s\n' "$({ sudo du -sh "$d" 2>/dev/null || true; } | cut -f1)" "$d"
  done
  [[ -t 0 ]] || die "Run this in a terminal: it asks before deleting."
  read -rp "Delete these copies for good? [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]] || die "Nothing was deleted."
  for d in "${dirs[@]}"; do
    say "Deleting $d"
    sudo rm -rf --one-file-system -- "$d" || die "Couldn't delete $d (see above)."
  done
  local mnt
  mnt=$(findmnt -n -o TARGET -T "$base" 2>/dev/null || true)
  if [[ -n "$mnt" ]]; then sudo fstrim "$mnt" >/dev/null 2>&1 || true; fi
  _migrate_umount
  ok "Deleted ${#dirs[@]} copies"
}

cmd_migrate() {
  local sub=${1:-}
  shift || true
  case $sub in
  backup) _migrate_backup "$@" ;;
  restore) _migrate_restore "$@" ;;
  clean) _migrate_clean "$@" ;;
  *) _migrate_usage ;;
  esac
}
