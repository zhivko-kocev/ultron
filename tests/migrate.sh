#!/usr/bin/env bash
# migrate: the newest complete backup is picked, build folders are skipped, rootless Docker's data is excluded.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
export XDG_RUNTIME_DIR=$HOME/run ULTRON_ROOT=$PWD
# shellcheck source=../lib/common.sh
source lib/common.sh
# shellcheck source=../lib/cmd/migrate.sh
source lib/cmd/migrate.sh
fail() {
  echo "FAIL migrate: $*"
  exit 1
}
b=$HOME/disk
mkdir -p "$b"/ultron-migration-2026-11-0{1,2}/home "$b"/ultron-migration-2026-11-02-0930/home
touch "$b"/ultron-migration-2026-11-0{1,2}/COMPLETE
[[ $(_migrate_pick "$b" 2>/dev/null) == "$b/ultron-migration-2026-11-02" ]] || fail "didn't pick the newest complete copy"
mkdir -p "$HOME"/Projects/{a/target,b/node_modules,c/target}
touch "$HOME"/Projects/a/Cargo.toml "$HOME"/Projects/b/package.json
[[ $(_migrate_build_dirs | sort | paste -sd' ') == "/Projects/a/target/ /Projects/b/node_modules/" ]] || fail "build folders"
printf '%s\n' "${MIGRATE_BACKUP_EXCLUDES[@]}" | grep -qx '/.local/share/docker/' || fail "backup copies Docker's data"
printf '%s\n' "${MIGRATE_RESTORE_EXCLUDES[@]}" | grep -qx '/.local/share/docker/' || fail "restore writes Docker's data"
echo "migrate ok"
