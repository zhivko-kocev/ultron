# ultron

A lightweight Arch Linux desktop built for working with coding agents. Install it, sign your agent in, and work: you don't need to know Arch, pacman or sway. If you do, everything is a plain file you can change.

- **Agent-first.** One agent, the boss, lives on workspace 1. Agents show you diffs, web pages, files and running terminals on their own workspaces, and ultron brings you to an agent only when it needs you *and* you've stopped typing. Away from the desk, the question goes to your phone.
- **Any agent.** [omp](https://github.com/can1357/oh-my-pi) ships by default; Claude Code, Codex, Gemini CLI and opencode are one command away, and any other CLI can be added. [Jocasta](https://github.com/zhivko-kocev/jocasta) is supported as a multi-thread boss.
- **Safe enough to let agents work.** Root needs your password in a popup that shows the exact command, every time. Docker is rootless. The disk is encrypted. Every package change has a snapshot you can boot.
- **Light.** sway, foot, fuzzel, mako and a bash status bar: about 570 MB of RAM at an idle desktop ([measured](docs/baseline.md)). No daemons you didn't ask for.
- **Yours.** One menu for everything (Super+Alt+Space), six themes, and a `~/.config/ultron/` folder where your settings, keys, packages and overrides live without forking anything.

## Install

You need a PC or laptop (x86-64, UEFI) whose disk can be **erased**, a USB stick with the [Arch Linux ISO](https://archlinux.org/download/), and a network connection. Intel and AMD graphics work out of the box; NVIDIA runs on the open driver and is untested.

1. Check the firmware settings ([docs/bios.md](docs/bios.md)) and boot the stick in **UEFI** mode. On Wi-Fi, connect first with `iwctl`.
2. Run:

       bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)

   It asks for a user name, host name, keyboard layout, an optional dotfiles repo, which disk to erase (you type `wipe`), and the passwords. Then it installs Arch.
3. Reboot, type the disk password, log in, and run:

       ~/Projects/ultron/bin/ultron install

4. Reboot. The desktop starts by itself and shows a short welcome.

Coming from another Linux install on the same disk? [docs/migrate.md](docs/migrate.md) carries your home folder across.

## Using it

| Key | |
|---|---|
| Super+Alt+Space | the menu: install and remove things, setup, themes, update, power |
| Super+K | every key, searchable |
| Super+Space / Super+Return | apps / terminal |
| Super+B | the boss agent |
| Super+A | go to whatever needs you; Super+Backspace goes back |
| Super+M | focus mode: agents can't move you |
| Super+Shift+S | screenshot a region and hand it to the boss |

Full list: [docs/keys.md](docs/keys.md).

| Workspace | What lives there |
|---|---|
| 1 boss | your boss agent, started at login |
| 2 review | diffs, files and test runs agents show you |
| 3 web | local pages agents open, in a separate preview browser |
| 4 watch | long-running terminals agents open |
| 5 code · 6 term · 7 chat · 8 · 9 | yours |
| 10 sys | system monitor, updates |

From a terminal, `ultron` does everything the menu does:

    ultron update                 # ultron itself, packages, tools, agents; then a health check
    ultron doctor                 # is everything all right?
    ultron pkg install            # search and install packages
    ultron dev add python         # languages and runtimes
    ultron agent add claude       # another agent; `ultron agent boss claude` makes it the boss
    ultron theme                  # switch theme
    ultron setup wifi             # also: bluetooth audio display keyboard browser git dotfiles …

Optional extras: `ultron install net` (Tailscale remote access), `ultron install ntfy` (phone alerts), `ultron install jocasta`.

**Undoing a bad update:** at the boot menu open Snapshots, pick one from before the update and boot it. If it's good, run `sudo limine-snapper-restore` there and reboot.

## Making it yours

Settings (`ultron conf`), themes, your own keys and monitor layout, extra packages, per-app overrides, hooks, and your dotfiles repo: [docs/customize.md](docs/customize.md).

## For agents

Agents learn the machine from `ultron guide` (rules) and `ultron info --json` (facts), show things with `ultron show …`, and call you with `ultron attention --raise "…"`. How to add agents and wire their notifications: [docs/agents.md](docs/agents.md).

## Security

What the encryption, the sudo popup and rootless Docker protect you from, and what they don't: [docs/security.md](docs/security.md). Read it before giving an agent free rein.

## What's inside

Arch Linux · LUKS2 + btrfs + snapper · Limine with bootable snapshots · greetd · sway · foot · fuzzel · mako · PipeWire · ufw · rootless Docker · mise · ollama (optional) · Tailscale and ntfy (optional).

| Folder | |
|---|---|
| `bootstrap.sh`, `install/` | the live-ISO installer |
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

Bootstrap from a fork or branch with `ULTRON_REPO=https://github.com/you/ultron ULTRON_REF=mybranch` in front of the bootstrap line. Every question has an `ULTRON_*` variable for unattended runs; they are listed at the top of `bootstrap.sh`.

All scripts pass `shellcheck`. Commits are scanned for secrets by gitleaks: run `git config core.hooksPath .githooks` once after cloning.

`v0.1.0` is the last single-machine version, before ultron became general.
