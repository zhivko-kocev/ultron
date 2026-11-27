# Contributing to ultron

Thanks for helping. ultron is a folder of bash scripts that turns a fresh Arch install into an agent-first desktop, so most changes are small and readable. This page is for people; [AGENTS.md](AGENTS.md) holds the same rules in the form coding agents read, and it is the source of truth for them.

## Proposing a change

- **A bug:** open an issue with the [bug form](https://github.com/zhivko-kocev/ultron/issues/new?template=bug.yml). It asks for `ultron doctor` and `ultron info` output and whether it happened in the VM or on hardware; that is usually enough to reproduce it.
- **An idea:** open an issue with the [idea form](https://github.com/zhivko-kocev/ultron/issues/new?template=idea.yml) before writing a large change, so we can agree on the shape first. Defaults and behaviour people rely on are decided in [docs/adr/](docs/adr/).
- **A small fix** (a typo, a wrong message, a clear bug with an obvious fix): send the pull request directly.
- **A security problem:** don't open a public issue; follow [docs/security.md](docs/security.md#reporting-a-problem).

## Setting up

    git clone https://github.com/zhivko-kocev/ultron
    cd ultron
    git config core.hooksPath .githooks    # gitleaks checks every commit for secrets

You need `bash`, `shellcheck` and `jq` for the checks, and QEMU for the VM. Nothing else is installed on your machine.

## The dev loop

**Never test install steps, stow or sway changes on the machine you work on.** Use the VM.

1. Edit. Each command is one file in `lib/cmd/`, each install step one file in `lib/install/`; shared helpers are in `lib/common.sh` (reuse them). The layout is described in [AGENTS.md](AGENTS.md#layout).
2. Run the checks (seconds, no root, no desktop):

       shellcheck -x bin/ultron lib/*.sh lib/*/*.sh bootstrap.sh vm/ultron-vm system/usr/lib/ultron/* home/bin/.local/bin/ask home/agentbin/.local/lib/ultron/agent-bin/sudo iso/build tests/run tests/*.sh
       bash tests/run

   Each `tests/*.sh` prints `<name> ok`. GitHub runs both on every push and pull request (`.github/workflows/check.yml`).
3. Commands that only touch your home folder can be tried with a throwaway one: `HOME=/tmp/fakehome bin/ultron conf list`.
4. Try it in the VM (`vm/ultron-vm`, state in `~/.local/share/ultron-vm`):

       vm/ultron-vm create            # download and verify the Arch ISO, make a 40G disk
       vm/ultron-vm run --iso         # boot the installer
       vm/ultron-vm run               # boot the installed system (--nogl if graphics misbehave)
       vm/ultron-vm type 'ls\n'       # type into the VM; `key ctrl-alt-f2`; `shot f.png` (needs --nogl)
       vm/ultron-vm ssh 'ultron doctor'   # port 2222 (needs sshd and your key in the VM)

   To install your branch, run the bootstrap line in the installer with `ULTRON_REPO=https://github.com/you/ultron ULTRON_REF=mybranch` in front of it. Every installer question has an `ULTRON_*` variable for unattended runs; they are listed at the top of `bootstrap.sh`.

   To test the ISO itself, build it and boot it:

       docker run --rm --privileged -v "$PWD":/src -w /src archlinux:latest bash iso/build mytag   # lands in out/
       ULTRON_VM_ISO=out/ultron-mytag-x86_64.iso vm/ultron-vm run --iso

## The rules

The full list is in [AGENTS.md](AGENTS.md#rules). In short:

- Bash only, `set -euo pipefail`, clean `shellcheck -x`, no `eval`. Mind the `set -e` traps listed there.
- Nothing personal in the repo: no user names, hosts, disks, monitors or personal apps. What differs per person is a setting or lives in `~/.config/ultron/`.
- Install steps are idempotent, and only the steps that need root use `sudo`. Third-party code runs without it (the exceptions are spelled out in AGENTS.md and [docs/security.md](docs/security.md)).
- Messages are for people who don't know Arch: say what happened and what to run next.
- A user-visible change updates the docs in the same commit: [docs/keys.md](docs/keys.md) for agent keys (`tests/keys.sh` checks it against the sway config), [docs/customize.md](docs/customize.md) for settings, the ultron skill (`home/skill/.agents/skills/ultron/SKILL.md`) for agent-facing behaviour. Use the words of [GLOSSARY.md](GLOSSARY.md).
- A change of a default, or of behaviour people rely on, gets a short record in `docs/adr/` (context, decision, the alternative you rejected and why).

## Commits and pull requests

- One change per pull request; keep unrelated clean-ups out.
- Commit subjects say what changes for the user, in plain words (`first boot: keep the autologin until the whole install passes`), with a body when the why isn't obvious.
- Add a line to the top section of [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- Fill in the pull request checklist: shellcheck, `bash tests/run`, docs updated, tried in the VM (say what you tried; "a fresh install with `ultron doctor` showing no FAIL, and `ultron update` once" for anything that touches install or update).
- No secrets, ever: keep the gitleaks hook on.

## Releases

- `main` is what `ultron update` pulls, so it should always install.
- A release is a pushed tag `v<version>` (for example `v0.3.0`). `.github/workflows/release.yml` builds `ultron-<tag>-x86_64.iso` and its `.sha256` with `iso/build` and publishes them as a GitHub release with generated notes. A tag with a `-` in it (`v0.3.0-rc1`) is published as a pre-release.
- Before tagging: `CHANGELOG.md` has a section for the version, the checks are green, and a fresh VM install from the release candidate's ISO reaches the desktop with `ultron doctor` passing.

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
