# Jocasta on ultron

[Jocasta](https://github.com/zhivko-kocev/jocasta) is an optional boss for workspace 1: a terminal program (Rust, ratatui) that runs a boss and many threads, each thread being an omp session. ultron builds it from source, starts it at login, and connects it to the desktop. Without it the boss is a plain agent (`omp` by default); see [agents.md](agents.md).

## Build and install

`ultron install jocasta` (run it whenever you like; `ultron update` reruns it when `main` moved):

1. Clones `https://github.com/zhivko-kocev/jocasta` to `~/Projects/jocasta` if missing. If it is on `main` and clean, runs `git pull --ff-only`.
2. Gets a build:
   - **In the VM:** set `ULTRON_JOCASTA_FROM` to a URL or folder that holds `jocasta-linux-x64.tar.gz` and its `.sha256`.
   - **Otherwise it builds:** `mise trust mise.toml`, `mise install --locked` for the tools in Jocasta's `mise.toml`, `mise exec -- bun install --frozen-lockfile`, then `mise run build` into `~/Projects/jocasta/dist`.
3. Installs with Jocasta's own script into `~/.local/lib/jocasta`:

       JOCASTA_INSTALL_DIR=$HOME/.local/lib/jocasta JOCASTA_INSTALL_NO_PATH=1 \
         JOCASTA_INSTALL_FROM=<build> sh ~/Projects/jocasta/scripts/install.sh

   The default Linux install folder (`~/.local/share/jocasta`) contains Jocasta's data folder, and an upgrade would delete it (review finding R1). `~/.local/lib/jocasta` avoids that.
4. Links `~/.local/bin/jocasta` to `~/.local/lib/jocasta/jocasta`.
5. Pins omp to the version named in Jocasta's README (`checked against omp X.Y.Z`) in `/etc/mise/conf.d/ultron-tools.toml`. This is the step's only root action and it comes first; the build then runs without root.
6. Runs `jocasta setup`. It shows each change to `~/.omp/agent/{config.yml,keybindings.yml,lsp.json,WATCHDOG.md}` as a diff: read it and type `y`.
7. Writes `~/.jocasta/agent/projects.yaml` if missing (roots `~/Projects`, and `~/Work` when it exists, depth 1).
8. Sets `BOSS=jocasta` and re-applies omp's settings that `jocasta setup` may have changed (the local commit model, and no sleep prevention so the typing guard keeps working).

Then close the old boss window (Super+W on workspace 1, confirm) and press Super+B.

## How it runs

- sway starts `ultron boss --start` at login. It opens `foot --app-id=ultron-boss` on workspace 1 running `$BOSS` with `~/.local/lib/ultron/agent-bin` first on PATH.
- Closing the boss window stops every thread; they resume on the next start. Super+W asks before closing it.
- Quit Jocasta with Ctrl+B, Alt+Q.

## Integration points

| Piece | What it does |
|---|---|
| Boss window | `foot --app-id=ultron-boss`, with `agent-bin` first on PATH so an agent's `sudo` goes through the popup that shows the command and folder ([security.md](security.md)) |
| `ultron-attentiond` | Follows `~/.local/share/jocasta/data/notifications.jsonl`. `blocked` → jump to workspace 1 after the typing guard, or the urgent mark in focus mode, or a phone push when away. `done`/`failed` → phone push only when away |
| Link router | `xdg-open http://127.0.0.1:<port>/…` (Jocasta's briefs) opens in the preview Chromium on workspace 3; other links go to your browser |
| mako | Styles Jocasta's notifications (`app-name=Jocasta`, blue border) |
| Bar | The `J` block: grey when running, red `J ✗` when not running, red `J ● needs you` while something is blocked |
| Keys | Super+B (boss), Super+N (Jocasta's New thread: Ctrl+B then Alt+N), Super+A (attention), Super+Shift+S (screenshot path for the boss), Super+Shift+J (friction note) |
| omp | Pinned to Jocasta's README version through mise |

## Fallback: plain omp

If Jocasta doesn't run, `ultron agent boss omp`, close the boss window and press Super+B. The boss is then a plain omp session with the same keys; the bar shows `boss: omp`. `ultron install jocasta` switches back.

## Known Linux blocker: Shift in foot (review item R12, [jocasta#1](https://github.com/zhivko-kocev/jocasta/issues/1))

Jocasta's `main` (as of `cd111f6`) loses Shift on typed characters in foot: "Hello!" arrives as "hello1". The fix is one flag (`REPORT_ALTERNATE_KEYS` in `src/frontier/shell/app.rs`), tested in the VM. Until it is on `main`:

- `ultron install jocasta` builds whatever `~/Projects/jocasta` has checked out when it isn't a clean `main`. So a checkout on a fix branch builds the fixed Jocasta, and `ultron update` leaves it alone.
- Or keep the boss on `omp` until the fix is merged.

## Improvement loop

1. **Capture:** press Super+Shift+J whenever Jocasta gets in your way. The note (time, focused window, your text) goes to `~/.local/share/ultron/jocasta-notes.md`.
2. **Triage:** ask the boss "triage my Jocasta notes". It groups the notes and the open review items into issue drafts and shows them to you in one form.
3. **File:** the ones you pick become `gh issue create` issues on `zhivko-kocev/jocasta`, each linking its record, as Jocasta's rules require.
4. **Build:** each issue becomes a Jocasta thread in project `jocasta`, following its AGENTS.md: grill, record, build, `mise run check`, review, then Finish as a merge or a PR according to the repo's `push:` setting.
5. **Ship to yourself:** quit Jocasta (Ctrl+B, Alt+Q), run `ultron update` in a terminal (it rebuilds and reinstalls Jocasta from `main`), then press Super+B. While Jocasta runs, `ultron update` and `ultron install jocasta` leave it alone: reinstalling under a running Jocasta breaks it (review item R10).
