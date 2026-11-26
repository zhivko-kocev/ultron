# shellcheck shell=bash
# step verify: ultron doctor (no sudo; `ultron doctor --root` adds the boot and snapshot checks).

step_verify() {
  "$ULTRON_ROOT/bin/ultron" doctor || die "doctor found problems (the FAIL lines above); fix them and rerun: ultron doctor"
}
