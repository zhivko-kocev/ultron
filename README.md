# ultron

A lightweight Arch Linux desktop built for working with coding agents. Install it, sign your agent in, and work: you don't need to know Arch, pacman or sway. If you do, everything is a plain file you can change.

- **Agent-first.** One agent, the boss, lives on workspace 1. Agents show you diffs, web pages, files and running terminals on their own workspaces, and ultron brings you to an agent only when it needs you *and* you've stopped typing. Away from the desk, the question goes to your phone.
- **Any agent.** [Jocasta](https://github.com/zhivko-kocev/jocasta) is the default boss: it runs many [omp](https://github.com/can1357/oh-my-pi) sessions as threads for your projects. omp, Claude Code, Codex, Gemini CLI and opencode can be the boss instead (one command away), and any other CLI can be added.
- **Safe enough to let agents work.** Root needs your password in a popup that shows the exact command, every time. Docker is rootless. The disk is encrypted. Every package change has a snapshot you can boot.
- **Light.** sway, foot, fuzzel, mako and a bash status bar: about 600 MB of RAM at an idle desktop before any agent starts ([measured](docs/baseline.md)). No daemons you didn't ask for.
- **Yours.** One menu for everything (Super+Alt+Space), six themes, and a `~/.config/ultron/` folder where your settings, keys, packages and overrides live without forking anything.

## Install

You need a PC or laptop (x86-64, UEFI) whose disk can be **erased**, a USB stick, and a network connection (cable or Wi-Fi). Intel and AMD graphics work out of the box; NVIDIA runs on the open driver and is untested.

1. Download `ultron-<version>-x86_64.iso` (and its `.sha256`) from the [latest release](https://github.com/zhivko-kocev/ultron/releases/latest) and write it to the stick with any image writer (balenaEtcher, Rufus in DD mode, or `dd`).
2. Check the firmware settings ([docs/bios.md](docs/bios.md)) and boot the stick in **UEFI** mode. The installer starts by itself. Without a cable it lists the Wi-Fi networks: pick yours and type its password.
3. It asks for a user name, host name, time zone, keyboard layout, an optional dotfiles repo, which disk to erase (you type `wipe`), and the passwords. Then it installs Arch.
4. Remove the stick, reboot, and type the disk password. The install continues by itself (it asks for your password once), then reboots into the desktop, which shows a short welcome.

If the install stops on the first boot, it says which step failed; fix that and run `ultron install --first-boot`.

**From a stock Arch ISO** ([archlinux.org/download](https://archlinux.org/download/)), boot it in UEFI mode, join Wi-Fi with `iwctl` if you need to, and run:

    bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)

The rest is the same as steps 3 and 4.

Coming from another Linux install on the same disk? [docs/migrate.md](docs/migrate.md) carries your home folder across.

## Using it

| Key | |
|---|---|
| Super+Alt+Space | the menu: install and remove things, setup, themes, update, power |
| Super+K | every key, searchable |
| Super+Space / Super+Return | apps / terminal |
| Super+B | the boss agent |
| Super+A | the oldest agent that needs you, else the newest window an agent showed you; Super+Backspace goes back to your last workspace |
| Super+M | focus mode: agents can't move you, notifications wait |
| Super+Shift+S | screenshot a region and hand it to the boss |

Full list: [docs/keys.md](docs/keys.md).

| Workspace | What lives there |
|---|---|
| 1 boss | your boss agent, started at login |
| 2 review | review pages, diffs, files and test runs agents show you |
| 3 web | local pages agents open, in a separate preview browser |
| 4 watch | long-running terminals agents open |
| 5 code · 6 term · 7 chat · 8 | yours |
| 9 browse | your browser |
| 10 sys | system monitor, updates |

From a terminal, `ultron` does everything the menu does:

    ultron update                 # ultron itself, packages, tools, agents; then a health check
    ultron doctor                 # is everything all right?
    ultron pkg install            # search and install packages
    ultron dev add python         # languages and runtimes
    ultron agent add claude       # another agent; `ultron agent boss claude` makes it the boss
    ultron theme                  # switch theme
    ultron setup wifi             # also: bluetooth audio display keyboard browser git dotfiles …

Optional extras: `ultron install net` (Tailscale remote access), `ultron install ntfy` (phone alerts).

**Undoing a bad update:** at the boot menu open Snapshots, pick one from before the update and boot it. If it's good, run `sudo limine-snapper-restore` there and reboot.

## Making it yours

Settings (`ultron conf`), themes, your own keys and monitor layout, extra packages, per-app overrides, hooks, and your dotfiles repo: [docs/customize.md](docs/customize.md).

## For agents

Agents learn the machine from `ultron guide` (rules) and `ultron info --json` (facts), show things with `ultron show …`, and call you with `ultron attention --raise "…"`. How to add agents and wire their notifications: [docs/agents.md](docs/agents.md).

## Security

What the encryption, the sudo popup and rootless Docker protect you from, and what they don't: [docs/security.md](docs/security.md). Read it before giving an agent free rein.

## What's inside

Arch Linux · LUKS2 + btrfs + snapper · Limine with bootable snapshots · greetd · SwayFX (stock sway as the fallback) · foot · fuzzel · mako · PipeWire · ufw · rootless Docker · mise (also per project, without a file in the repo) · ollama (on by itself with a graphics card of about 4 GB or more) · Tailscale and ntfy (optional) · a zsh starter with starship, zoxide, eza, bat, lazygit and lazydocker · in the menu: stay awake, night light, screen recording, colour and emoji pickers, font and background switchers.

| Folder | |
|---|---|
| `bootstrap.sh`, `install/`, `iso/` | the live-ISO installer and the ISO it ships on |
| `bin/ultron`, `lib/` | the `ultron` command and the install steps (bash) |
| `packages/` | package lists |
| `system/` | root-owned files, copied into `/` |
| `home/`, `templates/`, `themes/`, `skel/` | desktop config, themed templates, themes, starter shell |
| `agents/` | the agent registry |
| `vm/` | test the whole install in a QEMU VM |
| `docs/` | keys, customizing, agents, security, firmware, migration, Jocasta |

## Developing ultron

    vm/ultron-vm create        # download and verify the Arch ISO, make a 40G disk
    vm/ultron-vm run --iso     # boot the installer, then run the bootstrap line
    vm/ultron-vm run           # boot the installed system (--nogl if graphics misbehave)
    vm/ultron-vm type 'ls\n'   # type into the VM; `key ctrl-alt-f2`; `shot f.png` (needs --nogl)
    vm/ultron-vm ssh [cmd]     # port 2222 (needs sshd and your key in the VM)

To test an ultron ISO in the VM, put `ULTRON_VM_ISO=/path/to/ultron-<version>-x86_64.iso` in front of `vm/ultron-vm run --iso`. A pushed `v*` tag builds that ISO and publishes it as a release (`.github/workflows/release.yml`); to build one yourself: `docker run --rm --privileged -v "$PWD":/src -w /src archlinux:latest bash iso/build <tag>` (it lands in `out/`).

Bootstrap from a fork or branch with `ULTRON_REPO=https://github.com/you/ultron ULTRON_REF=mybranch` in front of the bootstrap line. Every question has an `ULTRON_*` variable for unattended runs; they are listed at the top of `bootstrap.sh`.

All scripts pass `shellcheck`. Commits are scanned for secrets by gitleaks: run `git config core.hooksPath .githooks` once after cloning.

`v0.1.0` is the last single-machine version, before ultron became general.
