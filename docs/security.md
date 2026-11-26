# Security: what ultron protects and what it doesn't

ultron is built for running coding agents as **your own user**, all day, on your own PC. That is convenient and it has a hard limit: anything an agent can do, a program that tricks the agent can do too. This page says plainly where the lines are.

## What you get

- **Full-disk encryption** (LUKS2). A stolen or switched-off PC shows nothing without the disk password. After you type it at boot, the desktop logs in by itself: the disk password is the login.
- **Snapshots you can boot.** Every package change takes a snapshot before and after; a bad update is undone from the boot menu.
- **A firewall** (ufw) that blocks incoming connections except Tailscale's own interface and what you list in `FIREWALL_ALLOW`. A port you take out of that list is closed again at the next `ultron install system` or update.
- **Rootless Docker.** Containers run as you, not as root, and there is no `docker` group (membership in it equals root). `ultron doctor` fails if that changes.
- **Root needs you, every time.** Agents get a `sudo` that asks through a popup showing the exact command and folder. No password is cached for them: two root commands mean two popups. When you are away, the request also goes to your phone (if phone alerts are set up); the popup waits 10 minutes, then the command fails.
- **Nothing listens on the internet.** Remote access is Tailscale only; the ntfy server for phone alerts listens on localhost and is published only inside your tailnet, with a password and a token.
- **Secrets stay out of git.** Both repos run gitleaks before every commit. Tokens belong in `~/.config/zsh/secrets.zsh` (never tracked).

## The sudo popup: informed consent, not a wall

The popup exists so an **honest agent can't become root without you noticing and agreeing**. It shows:

- the whole command, quoted the way a shell would need it, so nothing hides in odd spacing;
- the folder it runs in;
- a warning line when the request is a root shell, a root file edit, or would unlock sudo for a whole terminal.

It refuses commands too long to show in full, and commands that contain hidden text-direction characters.

Read it before typing your password. `sudo bash some-script.sh` shows you the script's name, not its contents.

What it is **not**: protection against a hostile program already running as you. Such a program could show a fake popup, put its own `sudo` earlier on your `PATH`, change your shell startup files, or edit ultron's own files in `~/Projects/ultron` before the next update. Linux does not separate one program of yours from another. The same is true on every desktop where agents run as your user.

## What ultron does about that limit

- **Root files come only from committed code.** `ultron install` and `ultron update` copy system files only if git tracks them, and if the ultron folder has local changes they show them and ask before doing anything as root.
- **No leftover root.** During `ultron install` the sudo ticket is alive while AUR packages build and your dotfiles installer runs (a fresh machine holds nothing yet); it is thrown away when the last root step is done, before tools from the internet (mise tools, agent CLIs) are installed. `ultron update` throws it away before any AUR package is built; yay then asks for your password itself when it installs one. Both drop it again on exit. An agent's `ultron install` or `update` stops at once: its `sudo` would ask once per command.
- **`ultron doctor` never asks for a password** unless you pass `--root` or `--deep`, so agents can run it freely.
- **Migration copies are flagged.** A backup made with `ultron migrate backup` is a plain, unencrypted copy of your home folder (browser profile, keyrings, agent logins). `doctor` warns for as long as one exists; delete it with `ultron migrate clean --from …` once you've checked the new system.

## What is still on you

- **What agents read.** A web page, an issue or a repository can contain instructions aimed at your agent. Agents with permission to run commands will sometimes follow them. Keep approvals on for work in repositories you don't trust.
- **Your login token files** (`~/.omp`, `~/.claude`, `gh`) are readable by every program you run.
- **Tailscale SSH.** `ultron install net` turns it on. Tailscale's default policy lets your own devices log in as any user, root included, without a password. If that is more than you want, change the `ssh` section of your tailnet's access controls (admin console → Access controls) to your user only, or to `"action": "check"`.
- **The boot chain is not signed.** Secure Boot is off, so someone with physical access and time could tamper with the unencrypted boot partition. Disk encryption protects your data at rest, not against that.
- **Your dotfiles repo's `install.sh`** runs during `ultron install` and `ultron update`, with sudo available. It is your code; treat changes to it that way.

## If you want a real boundary

Run untrusted agents under a second Linux account or inside a container or VM with only the project folder shared, so they cannot touch your login files or ultron itself. ultron does not set this up yet.

## Reporting a problem

Open an issue at <https://github.com/zhivko-kocev/ultron/issues>. For something you'd rather not post publicly, use GitHub's "Report a vulnerability" on the repository's Security tab.
