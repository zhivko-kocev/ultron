# ultron

A lightweight, fully custom Arch Linux + sway setup for agentic development on one desktop PC. The boss agent ([Jocasta](https://github.com/zhivko-kocev/jocasta)) lives on workspace 1; agents show you diffs, web pages and running terminals on their own workspaces, and ultron moves you to the boss only when it needs you and you've stopped typing.

- Arch on UEFI, LUKS2, btrfs, Limine with bootable snapper snapshots
- sway with a Gruvbox theme, greetd autologin after the disk password
- Rootless Docker, local AI (ollama, `qwen3:4b`), Tailscale, phone alerts through self-hosted ntfy
- One `ultron` command for everything; personal files live in [dotfiles](https://github.com/zhivko-kocev/dotfiles)

## Workspaces

| # | Name | What lives there |
|---|---|---|
| 1 | boss | Jocasta (boss and threads), started at login |
| 2 | review | `ultron show review`: diffs, test runs, PRs |
| 3 | web | localhost pages in the preview Chromium |
| 4 | watch | Live terminals agents open |
| 5 | code | Zed |
| 6 | term | Your terminals |
| 7 | chat | WhatsApp, Discord |
| 8, 9 | – | Free |
| 10 | sys | btop, `ultron update` |

## Keys

The usual ones: Super+Return terminal, Super+Space launcher, Super+W close, Super+1…0 workspaces, Super+Escape power menu. The agentic ones: Super+B boss, Super+Backspace back, Super+A attention, Super+N new thread, Super+Shift+S screenshot for the boss, Super+M focus mode, Super+Shift+J note a Jocasta friction point.

Press **Super+K** for the full list, or read [docs/keys.md](docs/keys.md).

## Install

1. Set up the BIOS ([docs/bios.md](docs/bios.md)) and boot the Arch ISO in **UEFI** mode.
2. In the live ISO, run:

       bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)

   It asks which disk to wipe (type `wipe`), a disk password and a user password, then installs Arch.
3. Reboot, type the disk password, log in, and run:

       ~/Projects/ultron/bin/ultron install

4. Reboot. sway starts by itself.
5. Optional: `ultron install jocasta` (the boss), `ultron install net` (Tailscale), `ultron install ntfy` (phone alerts).

Moving from an existing system: [docs/migrate.md](docs/migrate.md).

## Everyday

- `ultron update`: pulls this repo, reapplies the install, updates packages (with snapshots before and after), mise tools and Jocasta (only while Jocasta is closed), then runs `doctor`.
- `ultron doctor [--deep]`: checks the whole setup and prints PASS, WARN or FAIL per item.

## Testing in a VM

On any Arch host with KVM:

    vm/ultron-vm create        # download and check the Arch ISO, make a 40G disk
    vm/ultron-vm run --iso     # boot the installer (then run the bootstrap line above)
    vm/ultron-vm run           # boot the installed system (--nogl if graphics misbehave)
    vm/ultron-vm serve         # serve a Jocasta build to the VM at http://10.0.2.2:8765
    vm/ultron-vm type 'ls\n'   # type into the VM; `key ctrl-alt-f2` presses keys; `shot f.png` (needs --nogl)
    vm/ultron-vm ssh [cmd]     # ssh to the VM on 127.0.0.1:2222 (needs sshd and ~/.local/share/ultron-vm/id_vm.pub in the VM)
    vm/ultron-vm destroy

In the VM, install Jocasta from the host's build with `ULTRON_JOCASTA_FROM=http://10.0.2.2:8765 ultron install jocasta`.

## Jocasta

Jocasta is built from source and installed to `~/.local/lib/jocasta`; `BOSS=omp` in `~/.config/ultron/ultron.conf` falls back to a plain omp boss. See [docs/jocasta.md](docs/jocasta.md).

## Repo layout

- `bootstrap.sh`, `install/`: the live-ISO installer
- `bin/ultron`, `lib/`: the CLI and install steps
- `packages/`: package lists
- `system/`: root-owned files, copied (never linked) into `/`
- `home/`: stow packages for your home folder
- `vm/`: VM testing
- `docs/`: keys, BIOS, migration, Jocasta, footprint baseline

Commits are checked for secrets by gitleaks: run `git config core.hooksPath .githooks` once after cloning.
