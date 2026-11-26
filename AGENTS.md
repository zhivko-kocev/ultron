# Working on ultron (for agents and people)

ultron is a set of bash scripts that turn a fresh Arch install into an agent-first sway desktop. Read `README.md` for what it does; this file is about changing it.

## Layout

- `bin/ultron`: dispatcher. `ultron foo-bar ARGS` sources `lib/cmd/foo-bar.sh` and calls `cmd_foo_bar ARGS`.
- `lib/common.sh`: shared helpers (settings, themes, sway queries, menus, sudo keepalive). Reuse them.
- `lib/cmd/*.sh`: one command per file. `lib/install/*.sh`: one install step per file (`step_<name>`), run by `lib/cmd/install.sh` in the order of `ULTRON_STEP_ORDER`.
- `bootstrap.sh`: runs as root in the Arch live ISO; standalone (it cannot source `lib/`). `iso/build` puts it on an Arch live ISO that starts it (built by `.github/workflows/release.yml` for every `v*` tag).
- `home/<package>/…`: stow packages linked into `~`. `templates/` + `themes/` are rendered by `ultron apply`. `system/…` is copied into `/` as root (tracked files only).
- `packages/*.txt`: package lists. `agents/registry.tsv`: known agent CLIs.
- `vm/ultron-vm`: QEMU test VM.

## Rules

1. Bash only, `set -euo pipefail` (inherited from `bin/ultron`). Every file passes `shellcheck -x`. No `eval`.
2. Under `set -e`, a function must not end with `[[ … ]] && cmd`: use `if`. A command substitution whose failure you handle needs `|| true` inside it. Pipelines fail when any part fails (`pipefail`): `grep`, `sed` on a missing file and `head` on a long stream all count.
3. Nothing personal in the repo: no user names, hosts, disks, monitors, personal apps. What differs per person is a setting (`_CONF_DEFAULT` in `lib/common.sh`) or lives in `~/.config/ultron/`.
4. Steps are idempotent: running `ultron install` twice changes nothing the second time.
5. Root: only install steps use `sudo`, and only steps listed in `ULTRON_ROOT_STEPS`. Third-party code (mise tools, builds) runs after `sudo_drop`, with one exception: during `ultron install` the ticket is alive while AUR packages build and the dotfiles installer runs (a fresh machine holds nothing yet). `ultron update` drops it before AUR builds. `ultron doctor` must work without sudo.
6. Messages are for people who don't know Arch: say what happened and what to run next.
7. A user-visible change updates the docs in the same commit: `ultron keys` (Super+K) reads the keys from `home/sway/.config/sway/config` itself, and `docs/keys.md` lists exactly the bindings under its `# Agentic keys` comment (`tests/keys.sh` checks both); settings are listed in `docs/customize.md`; agent-facing behaviour in `home/skill/.agents/skills/ultron/SKILL.md`. Use the words of `GLOSSARY.md` (Jocasta's tabs are "Jocasta tabs", never "workspaces"). A change of a default or of behaviour people rely on gets a short record in `docs/adr/` (context, decision, rejected alternative).
8. No secrets in commits: `git config core.hooksPath .githooks` enables the gitleaks check.

## Testing

Never test install steps, stow, or sway changes on the machine you work on. Use the VM:

    vm/ultron-vm create && vm/ultron-vm run --iso     # then run bootstrap.sh with ULTRON_REF=<your branch>
    ULTRON_VM_ISO=out/ultron-<tag>-x86_64.iso vm/ultron-vm run --iso   # or boot an ultron ISO (iso/build)
    vm/ultron-vm run                                  # the installed system
    vm/ultron-vm ssh 'ultron doctor'                  # after putting your key and sshd in the VM

Commands that only read or write under `$HOME` can be tried with a throwaway home: `HOME=/tmp/fakehome bin/ultron conf list`.

Self-checks (plain bash, no root, no desktop): `bash tests/run`. Each `tests/*.sh` prints `<name> ok`; the GitHub check workflow runs shellcheck and them on every push.

Before a pull request: `shellcheck -x bin/ultron lib/*.sh lib/*/*.sh bootstrap.sh vm/ultron-vm system/usr/lib/ultron/* home/bin/.local/bin/ask home/agentbin/.local/lib/ultron/agent-bin/sudo iso/build tests/run tests/*.sh`, `bash tests/run`, a fresh VM install with `ultron doctor` showing no FAIL, and `ultron update` run once on that VM.
