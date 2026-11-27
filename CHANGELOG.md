# Changelog

What changed for people using ultron, newest first. Each version is a `v*` tag; from 0.3.0 on, its release page has the installer ISO.

## 0.3.0

**Install like a product**
- Each release ships an installer ISO (`ultron-<version>-x86_64.iso` with its `.sha256`): boot it and the installer starts by itself. The `curl` line on a stock Arch ISO still works.
- The installer lists Wi-Fi networks and joins the one you pick; the network is carried into the installed system.
- After the first reboot the install continues by itself (it asks for your password once), runs `ultron doctor`, and reboots into the desktop. A failed step says what to fix and how to retry (`ultron install --first-boot`).

**Agents and attention**
- Jocasta is the default boss. mise installs it from its releases, with checksums and build attestations checked; nothing is built on the PC. omp follows its latest release instead of a pinned version.
- Showing never moves you: `ultron show` places the window as a tab on workspace 2, 3 or 4 and the bar marks the workspace (`new 2`). Preview windows don't take focus.
- Attention requests queue, one per waiting window, oldest first. The bar shows `● N need you`; Super+A walks the requests, then every workspace with unseen windows; `ultron attention --list` prints them. A request's notification goes away when you reach its window.
- Windows an agent shows with a tag (`--tag`, or the Jocasta thread it runs for) close by themselves once the thread's worktree is gone. New: `ultron show code FILE:LINE`, `ultron show list`, `ultron show close --tag`.
- Agents' visible browser tabs land on workspace 3; your own browser moved to workspace 9 (`9:browse`).
- Focus mode (Super+M) also holds notifications.
- Two agents asking for `sudo` at once get two popups, one after the other.
- Jocasta's colours follow the ultron theme (`~/.jocasta/agent/palette.json`), and its questions and Allow requests reach the attention queue and your phone.

**Desktop**
- Effects: SwayFX (rounded corners, shadows, window animations) is on by default (`EFFECTS`), with stock sway as the automatic fallback when an update needs SwayFX rebuilt.
- New settings `FONT` and `BACKGROUND`, with Style → Font and Style → Background in the menu.
- Menu: new Toggle section (focus mode, stay awake, night light) and Capture section (region, full screen, for the boss, screen recording, colour picker, emoji picker). New commands `ultron toggle` and `ultron pick`; `ultron clip` became `ultron pick clip` (Super+Ctrl+V), emoji is Super+Ctrl+E.
- The starter zsh has starship, zoxide, eza, bat, lazygit and lazydocker, `ff` to find a file with a preview, and short git aliases. The font is JetBrains Mono Nerd Font.
- Per-project tools without touching the repo: `ultron dev project` keeps a project's tools, environment and tasks in `~/.config/mise/config.<repo>.toml`, loaded by your shell and by Jocasta's threads in every worktree.
- Local AI is automatic (`LOCAL_AI=auto`): on when a graphics card with about 4 GB of memory or more is found.
- Super+K reads every key from the sway config itself, so it is always current. Super+Backspace is sway's own back-and-forth (the same as Super+Ctrl+Tab).

**Safer, more predictable**
- `ultron update` drops the sudo ticket before building AUR packages.
- An interrupted boot-menu update restores the previous `/boot/limine.conf`.
- Ports and mounts you remove from `FIREWALL_ALLOW` and `MOUNTS` are taken out of the firewall and `/etc/fstab` again; rules you added by hand are left alone.
- `ultron pkg` and `ultron update` wait for each other instead of colliding; settings writes are locked.
- Agents get a clear message when they try to run `ultron install` or `update` (it must run in your own terminal).
- Default apps you chose yourself are no longer overwritten; migration skips rootless Docker's data; `doctor` doesn't wake Docker.
- AUR builds make no debug packages and leave no Gradle daemon running.

**For contributors**
- Self-checks in `tests/` (`bash tests/run`) and a GitHub workflow running them with shellcheck on every push.
- `GLOSSARY.md` and decision records in `docs/adr/`.
- `vm/ultron-vm run --iso` boots an ultron ISO with `ULTRON_VM_ISO`; `vm/ultron-vm serve` is gone.
- Removed: `ultron back`, `ultron clip`, `jump --app-id`, the `pacman` and `verify` install steps (`ultron install` ends with `ultron doctor`).

## 0.2.0

The general install: any user and machine, themes, settings and overrides in `~/.config/ultron/`, an agent-agnostic boss and the menu. See the [v0.2.0 tag](https://github.com/zhivko-kocev/ultron/tree/v0.2.0).

## 0.1.0

The last single-machine version, before ultron became general ([v0.1.0 tag](https://github.com/zhivko-kocev/ultron/tree/v0.1.0)).
