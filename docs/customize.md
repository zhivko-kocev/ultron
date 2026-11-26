# Making ultron yours

You never need to edit the ultron folder or fork it. Everything you change lives in `~/.config/ultron/`, survives `ultron update`, and can be kept in your own dotfiles repo.

```
~/.config/ultron/
  ultron.conf        settings for this machine (KEY=value)
  conf.d/*.conf      more settings files (ultron.conf wins)
  packages.txt       extra packages, one per line
  sway/*.conf        your sway config: keys, monitors, rules
  foot.ini  fuzzel.ini  mako  swaylock  gtk.ini    per-app overrides
  themes/*.conf      your own themes
  agents.tsv         extra agent CLIs
  hooks/post-install  hooks/post-update            your scripts
  generated/         written by ultron; don't edit
```

After editing a file by hand, run `ultron apply` (or press Super+Shift+C for sway-only changes).

## Settings

`ultron conf` lists every setting with its value; `ultron conf set KEY VALUE` changes one and applies it. Most also have an entry under **Setup** in the menu (Super+Alt+Space).

| Setting | Default | What it does |
|---|---|---|
| `BOSS` | `omp` | The agent in the boss window on workspace 1: any command, e.g. `claude`, `codex`, `jocasta` |
| `BROWSER` | `chromium` | The everyday browser (Super+Shift+Return, links) |
| `THEME` | `gruvbox-dark` | Colour theme |
| `KEYBOARD`, `KEYBOARD_VARIANT` | `us`, empty | Keyboard layouts, e.g. `us,de` |
| `LOCAL_AI` | `yes` | Run a local model with ollama (`no` removes it from the install) |
| `ASK_MODEL` | `qwen3:4b` | The local model `ask` uses |
| `OLLAMA_GPU` | `auto` | Which GPU ollama uses: `auto`, a Vulkan device number, or `none` |
| `DOTFILES_REPO` | empty | Your dotfiles repo (git URL); cloned to `~/Projects/dotfiles`, its `install.sh` is run |
| `MOUNTS` | empty | Extra disks to mount at boot: `LABEL=data:/mnt/data` (space-separated; `UUID=` and `/dev/…` work too) |
| `FIREWALL_ALLOW` | empty | Extra ports to open: `8080/tcp 53317/udp` |
| `AWAY_AFTER` | `300` | Seconds without input before you count as away (alerts go to your phone) |
| `LOCK_AFTER` | `600` | Seconds before the screen locks; `0` = never |
| `SCREEN_OFF_AFTER` | `900` | Seconds before the screen turns off; `0` = never |

`MOUNTS`, `FIREWALL_ALLOW`, `LOCAL_AI` and `OLLAMA_GPU` change the system: run `ultron install` after changing them.

## Themes

`ultron theme` picks one; `ultron theme --list` shows them. It recolours sway, the bar, terminals (new ones), the launcher, notifications, the lock screen and GTK apps.

Your own theme: copy one from the ultron folder's `themes/` to `~/.config/ultron/themes/mine.conf`, change the colours (hex without `#`), then `ultron theme mine`.

## Keys, monitors and window rules (sway)

Put any sway config in `~/.config/ultron/sway/NAME.conf`. It is read last, so it wins.

```
# ~/.config/ultron/sway/keys.conf
bindsym $mod+Shift+f exec nautilus
bindsym $mod+g exec ultron webapp open github

# ~/.config/ultron/sway/monitor.conf
output DP-1 mode 2560x1440@144Hz scale 1.25

# ~/.config/ultron/sway/rules.conf
assign [app_id="^org.telegram.desktop$"] workspace 7:chat
```

To replace one of ultron's keys, bind the same key again in your file: write `bindsym --no-warn $mod+…` so sway doesn't flag the override. **Setup → Display** in the menu creates a monitor file listing your outputs.

The workspace names are `1:boss 2:review 3:web 4:watch 5:code 6:term 7:chat 8 9 10:sys`. Workspaces 2, 3 and 4 are where agents open things for you; keep them free.

## Terminal, launcher, notifications, lock screen, GTK

Each has an override file that ultron never overwrites:

| File | App | Format |
|---|---|---|
| `foot.ini` | terminal | foot's: e.g. `[main]` then `font=Fira Code:size=12` |
| `fuzzel.ini` | launcher and menus | fuzzel's |
| `mako` | notifications | mako's global options (no `[sections]`) |
| `swaylock` | lock screen | one option per line, e.g. `image=/path/to.png` |
| `gtk.ini` | GTK apps | `key=value` lines for `[Settings]` |

## Packages

Install from the menu (**Install → Package**) or `ultron pkg install`: official and AUR packages in one searchable list. What you install is recorded in `~/.config/ultron/packages.txt`, and `ultron install` on a new machine installs that list again.

Languages and runtimes: **Install → Dev tool** or `ultron dev add python` (managed by mise, per user, no root).

Web apps: **Install → Web app** or `ultron webapp add WhatsApp https://web.whatsapp.com --ws 7` makes a launcher entry that opens in its own window, optionally always on one workspace.

## Agents

See [agents.md](agents.md). Short version: `ultron agent add claude`, `ultron agent boss claude`.

## Hooks

`~/.config/ultron/hooks/post-install` and `post-update`, if executable, run at the end of `ultron install` and `ultron update`, as you, without root.

## Dotfiles

Set `DOTFILES_REPO` (or answer the question at install time). ultron clones it to `~/Projects/dotfiles` and runs its `install.sh` early in the install, so your repo can ship any of the files above (for example a stow package containing `.config/ultron/conf.d/10-mine.conf`, `packages.txt` and `sway/mine.conf`) and a new machine comes up exactly like your last one.

Without dotfiles, ultron gives you a starter zsh config (`~/.zshrc`) that is yours to edit.

## Local model tuning

ultron writes `/etc/systemd/system/ollama.service.d/ultron.conf`. Put your own ollama environment (for example `OLLAMA_CONTEXT_LENGTH`) in a second file next to it, such as `local.conf`; no ultron step touches that one.

## Changing ultron itself

It is a folder of bash scripts: `~/Projects/ultron`. `ultron update` only pulls when that folder has no local changes, so keep your changes on a fork (set the fork as `origin`) or send them upstream.
