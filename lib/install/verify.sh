# shellcheck shell=bash
# step verify: ultron doctor.

step_verify() {
  "$ULTRON_ROOT/bin/ultron" doctor || die "doctor found problems (the FAIL lines above); fix them and rerun: ultron doctor"
}
