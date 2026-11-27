## What and why

<!-- What changes for the user, and why. Link the issue if there is one. -->

## Checklist

- [ ] `shellcheck -x bin/ultron lib/*.sh lib/*/*.sh bootstrap.sh vm/ultron-vm system/usr/lib/ultron/* home/bin/.local/bin/ask home/agentbin/.local/lib/ultron/agent-bin/sudo iso/build tests/run tests/*.sh` is clean
- [ ] `bash tests/run` passes
- [ ] Docs updated (README, `docs/`, `docs/keys.md`, the ultron skill, `GLOSSARY.md` words, `CHANGELOG.md`; a record in `docs/adr/` for a changed default)
- [ ] Tried in the VM (`vm/ultron-vm`): <!-- what you ran; for install or update changes, a fresh install with `ultron doctor` showing no FAIL and one `ultron update` -->
- [ ] Nothing personal and no secrets in the diff
