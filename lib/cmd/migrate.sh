# shellcheck shell=bash
# ultron migrate backup [--exclude PATTERN]... : copy home, /etc and Docker volumes to the projects SSD.
# ultron migrate restore [--dir D] [--dry-run]  : bring that copy back on ultron (docs/migrate.md).

MIGRATE_PREVIEW=/tmp/ultron-restore-preview.txt

# Static backup excludes (rsync patterns anchored at the home folder).
MIGRATE_BACKUP_EXCLUDES=(
  /.cache/ /.local/share/mise/ /.local/share/Trash/ /.local/share/ultron-vm/ /.stremio-server/
  /.rustup/ /.cargo/registry/ /.cargo/git/ /.npm/_cacache/ /.bun/install/cache/
  "/Downloads/archlinux-*.iso"
)

# Static restore excludes: Omarchy's desktop, files ultron and dotfiles now own, the two repos.
MIGRATE_RESTORE_EXCLUDES=(
  /.config/hypr/ /.config/omarchy/ /.local/share/omarchy/ /.local/state/omarchy/ /.config/uwsm/
  /.config/waybar/ /.config/walker/ /.config/elephant/ /.config/quickshell/ /.config/alacritty/
  /.config/ghostty/ /.config/kitty/ /.config/swayosd/ /.config/mako/ /.config/starship.toml
  /.config/xdg-desktop-portal/ /.config/fontconfig/ /.config/mimeapps.list /.config/systemd/
  /.config/environment.d/ /.config/herdr/ /.local/state/herdr/ /.local/share/herdr/ /.config/mise/
  /.local/state/mise/ /.local/share/applications/ /.agents/ /.bashrc /.bash_profile /.bash_logout
  /.profile /.XCompose /.zshrc /.zshenv /.config/chrome-flags.conf /.config/chromium-flags.conf
  /.config/zed/ /.config/git/ /Projects/ultron/ /Projects/dotfiles/
)

_migrate_refuse_running() {
  local p running=()
  for p in "$@"; do
    pgrep -x "$p" >/dev/null 2>&1 && running+=("$p")
  done
  ((${#running[@]} == 0)) || die "Close these first (they change files while they run): ${running[*]}"
}

# _migrate_build_dirs: Rust target/ next to Cargo.toml and node_modules/ next to package.json
# under ~/Projects and ~/Work, as rsync patterns anchored at home.
_migrate_build_dirs() {
  local roots=() r d
  for r in "$HOME/Projects" "$HOME/Work"; do
    [[ -d "$r" ]] && roots+=("$r")
  done
  ((${#roots[@]})) || return 0
  while IFS= read -r -d '' d; do
    case ${d##*/} in
    target) [[ -f "${d%/*}/Cargo.toml" ]] || continue ;;
    node_modules) [[ -f "${d%/*}/package.json" ]] || continue ;;
    esac
    printf '/%s/\n' "${d#"$HOME/"}"
  done < <(find "${roots[@]}" -type d \( -name target -o -name node_modules \) -prune -print0 2>/dev/null)
}

# _migrate_transfer_bytes RSYNC_ARGS...: "Total transferred file size" of a dry run.
_migrate_transfer_bytes() {
  sudo rsync -aHAX --dry-run --mkpath --stats "$@" 2>/dev/null |
    sed -n -E 's/^Total transferred file size: ([0-9,]+).*/\1/p' | tr -d ,
}

_migrate_backup() {
  local extra=()
  while (($#)); do
    case $1 in
    --exclude)
      [[ -n "${2:-}" ]] || die "--exclude needs a pattern, like --exclude /Downloads/"
      extra+=("$2")
      shift 2
      ;;
    *) die "usage: ultron migrate backup [--exclude PATTERN]..." ;;
    esac
  done
  ((EUID != 0)) || die "Run this as your user, not root."
  _migrate_refuse_running omp chrome chromium jocasta
  sudo_keepalive

  # Mount the SSD (no fstab change); unmount at the end only if mounted here.
  local mounted_here=0
  if ! mountpoint -q "$SSD_MOUNT"; then
    say "Mounting the projects SSD at $SSD_MOUNT"
    sudo mkdir -p "$SSD_MOUNT"
    sudo mount "UUID=$SSD_UUID" "$SSD_MOUNT" || die "Couldn't mount the projects SSD (UUID $SSD_UUID). Is it connected?"
    mounted_here=1
  fi
  ls -la "$SSD_MOUNT"
  df -h "$SSD_MOUNT"

  local dest
  dest=$SSD_MOUNT/ultron-migration-$(date +%F)
  [[ -e "$dest" ]] && dest+=-$(date +%H%M)
  [[ ! -e "$dest" ]] || die "$dest already exists; wait a minute and run this again."

  local list
  list=$(mktemp)
  {
    printf '%s\n' "${MIGRATE_BACKUP_EXCLUDES[@]}"
    ((${#extra[@]})) && printf '%s\n' "${extra[@]}"
    _migrate_build_dirs
  } >"$list"
  say "Excluding $(wc -l <"$list") patterns (caches, build folders, the VM, ISOs)"

  # Space check: dry-run size x 1.1 must fit.
  say "Measuring what will be copied (dry run)"
  local need_home need_etc need avail
  need_home=$(_migrate_transfer_bytes --exclude-from="$list" "$HOME/" "$dest/home/")
  need_etc=$(_migrate_transfer_bytes /etc/ "$dest/etc/")
  [[ -n "$need_home" ]] || die "The rsync dry run failed; run it by hand to see why: sudo rsync -aHAX --dry-run --stats --exclude-from=$list ~/ $dest/home/"
  need=$(((need_home + ${need_etc:-0}) * 11 / 10))
  avail=$(df --output=avail -B1 "$SSD_MOUNT" | tail -n1 | tr -dc '0-9')
  echo "Needs about $(numfmt --to=iec "$need") (with 10 % margin); free: $(numfmt --to=iec "$avail")"
  if ((need > avail)); then
    rm -f "$list"
    ((mounted_here)) && sudo umount "$SSD_MOUNT"
    die "Not enough space on the SSD. Run again with --exclude /Downloads/ (and copy Downloads to another disk)."
  fi

  sudo mkdir -p "$dest/home" "$dest/etc" "$dest/docker-volumes"

  # Docker volumes (Omarchy's Docker is rootful).
  if have docker && sudo docker info >/dev/null 2>&1; then
    local v vols=()
    mapfile -t vols < <(sudo docker volume ls -q)
    say "Exporting ${#vols[@]} Docker volumes"
    for v in "${vols[@]}"; do
      echo "  $v"
      sudo docker run --rm -v "$v:/v:ro" -v "$dest/docker-volumes:/b" alpine tar -czf "/b/$v.tgz" -C /v . ||
        die "Exporting Docker volume $v failed."
    done
  else
    warn "Docker isn't running: no volumes exported"
  fi

  say "Copying home to $dest/home/"
  sudo rsync -aHAX --info=progress2 --exclude-from="$list" "$HOME/" "$dest/home/" ||
    die "Copying home failed (see above). The partial copy is in $dest."

  say "Copying /etc and the package lists"
  sudo rsync -aHAX /etc/ "$dest/etc/" || die "Copying /etc failed."
  local tmp
  tmp=$(mktemp)
  pacman -Qqe >"$tmp" && sudo install -m 0644 "$tmp" "$dest/pacman-Qqe.txt"
  pacman -Qqm >"$tmp" || true
  sudo install -m 0644 "$tmp" "$dest/pacman-Qqm.txt"
  crontab -l >"$tmp" 2>/dev/null || : >"$tmp"
  sudo install -m 0644 "$tmp" "$dest/crontab.txt"
  rm -f "$tmp"

  # The copy must be complete: a second dry run shows no changes.
  say "Checking the copy (second dry run)"
  local changes
  changes=$(sudo rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$HOME/" "$dest/home/")
  if [[ -n "$changes" ]]; then
    warn "Files changed during the copy; copying them again:"
    printf '%s\n' "$changes" | head -n 20 >&2
    sudo rsync -aHAX --exclude-from="$list" "$HOME/" "$dest/home/"
    changes=$(sudo rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$HOME/" "$dest/home/")
    if [[ -n "$changes" ]]; then
      printf '%s\n' "$changes" | head -n 20 >&2
      rm -f "$list"
      die "Files keep changing in your home (above). Close the programs that write them, then run ultron migrate backup again."
    fi
  fi
  rm -f "$list"

  sync
  local size
  size=$(sudo du -sh "$dest" | cut -f1)
  if ((mounted_here)); then
    sudo umount "$SSD_MOUNT"
    ok "Unmounted $SSD_MOUNT"
  fi
  ok "Backup done: $dest ($size)"
}

_migrate_restore() {
  local dir="" dry=0
  while (($#)); do
    case $1 in
    --dir)
      [[ -n "${2:-}" ]] || die "--dir needs a folder"
      dir=$2
      shift 2
      ;;
    --dry-run)
      dry=1
      shift
      ;;
    *) die "usage: ultron migrate restore [--dir D] [--dry-run]" ;;
    esac
  done
  ((EUID != 0)) || die "Run this as your user, not root."
  _migrate_refuse_running chrome chromium

  if [[ -z "$dir" ]]; then
    mountpoint -q "$SSD_MOUNT" || die "$SSD_MOUNT isn't mounted. Check the SSD is connected (ultron doctor), or pass --dir."
    dir=$(find "$SSD_MOUNT" -mindepth 1 -maxdepth 1 -type d -name 'ultron-migration-*' | sort | tail -n1)
    [[ -n "$dir" ]] || die "No ultron-migration-* folder in $SSD_MOUNT."
  fi
  dir=${dir%/}
  [[ -d "$dir/home" ]] || die "$dir has no home/ folder: is it an ultron migration copy?"
  say "Restoring from $dir"

  # Excludes: every link in ~ that points into the two repos (stow links), then the static list.
  local ur dr list l real n_links=0
  ur=$(readlink -f "$HOME/Projects/ultron")
  dr=$(readlink -f "$HOME/Projects/dotfiles" 2>/dev/null || printf '%s' "$HOME/Projects/dotfiles")
  list=$(mktemp)
  while IFS= read -r -d '' l; do
    real=$(readlink -f "$l" 2>/dev/null || true)
    if [[ "$real" == "$ur" || "$real" == "$ur/"* || "$real" == "$dr" || "$real" == "$dr/"* ]]; then
      printf '/%s\n' "${l#"$HOME/"}" >>"$list"
      n_links=$((n_links + 1))
    fi
  done < <(find "$HOME" -xdev \( -path "$HOME/Projects/ultron" -o -path "$HOME/Projects/dotfiles" \) -prune -o -type l -print0)
  printf '%s\n' "${MIGRATE_RESTORE_EXCLUDES[@]}" >>"$list"
  echo "Skipping $n_links linked files and ${#MIGRATE_RESTORE_EXCLUDES[@]} Omarchy/ultron paths"

  # Plain rsync as the user, not sudo: the backup kept uid 1000 ownership, so every file the
  # user owned is readable here, and nothing root-owned can land in ~. -o/-g are ignored for a
  # non-root rsync, so restored files belong to the user. Unreadable files are reported (exit 23).
  if ((dry)); then
    rsync -aHAX --dry-run --itemize-changes --exclude-from="$list" "$dir/home/" "$HOME/" >"$MIGRATE_PREVIEW" ||
      warn "rsync reported problems (see above)"
    local count
    count=$(grep -c . "$MIGRATE_PREVIEW" || true)
    say "Dry run: $count changes (full list: $MIGRATE_PREVIEW). By top-level folder:"
    cut -d' ' -f2- "$MIGRATE_PREVIEW" | awk -F/ 'NF { print $1 }' | sort | uniq -c | sort -rn | head -n 25
    if [[ -d "$dir/docker-volumes" ]]; then
      local tgz
      for tgz in "$dir"/docker-volumes/*.tgz; do
        [[ -e "$tgz" ]] && echo "  docker volume: $(basename "$tgz" .tgz)"
      done
    fi
    rm -f "$list"
    ok "Nothing was changed. Run without --dry-run to restore."
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

  if [[ -d "$dir/docker-volumes" ]]; then
    local tgz v
    export DOCKER_HOST=${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}
    for tgz in "$dir"/docker-volumes/*.tgz; do
      [[ -e "$tgz" ]] || continue
      v=$(basename "$tgz" .tgz)
      say "Importing Docker volume $v (rootless)"
      docker volume create "$v" >/dev/null
      docker run --rm -v "$v:/v" -v "$dir/docker-volumes:/b:ro" alpine tar -xzf "/b/$v.tgz" -C /v ||
        die "Importing Docker volume $v failed."
    done
  fi

  xdg-user-dirs-update
  ok "Restore done. Next: ultron install jocasta"
}

cmd_migrate() {
  local sub=${1:-}
  shift || true
  case $sub in
  backup) _migrate_backup "$@" ;;
  restore) _migrate_restore "$@" ;;
  *) die "usage: ultron migrate backup [--exclude PATTERN]... | restore [--dir D] [--dry-run]" ;;
  esac
}
