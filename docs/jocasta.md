# Jocasta on ultron

[Jocasta](https://github.com/zhivko-kocev/jocasta) is the default boss for workspace 1: a terminal program (Rust, ratatui) that runs a boss and many threads, each thread being an omp session on its own branch and worktree. Its per-project and per-thread tabs are **Jocasta tabs**, inside the boss window; they are not sway workspaces. ultron installs it from its releases, starts it at login, and connects it to the desktop. Any other agent can be the boss instead (`omp` ships too); see [agents.md](agents.md). Why it is the default: [adr/0001](adr/0001-jocasta-is-the-default-boss.md).

## Install

mise installs Jocasta from its GitHub releases with the other agent tools (`"github:zhivko-kocev/jocasta" = "latest"` in `/etc/mise/conf.d/ultron-tools.toml`, step `agents`), checking the release's checksums and build attestations; nothing is built on the PC. `ultron update` upgrades it with `mise upgrade` and, when its version changed while it runs, tells you to restart it (Ctrl+B, Alt+Q, then Super+B). omp is not pinned: mise keeps it at the latest release.

The step `ultron install jocasta` (a default step; it does nothing when `BOSS` isn't `jocasta`) needs no root:

1. Checks that `jocasta --version` runs.
2. Runs `jocasta setup --yes` when `~/.jocasta/agent/setup/` holds no markers (setup never ran here), so a fresh install asks nothing. Later setup changes are listed by Jocasta when it starts: run `jocasta setup` to read and apply them.
3. Writes `~/.jocasta/agent/projects.yaml` if missing (roots `~/Projects`, and `~/Work` when it exists, depth 1).
4. Writes the palette (below).

The first thing to do in a fresh boss pane is `/login` (omp's sign-in).

## How it runs

- sway starts `ultron boss --start` at login. It opens `foot --app-id=ultron-boss` on workspace 1 running `$BOSS` with `~/.local/lib/ultron/agent-bin` first on PATH, so an agent's `sudo` goes through the popup that shows the command and folder ([security.md](security.md)).
- Closing the boss window stops every thread; they resume on the next start. Super+W asks before closing it.
- Quit Jocasta with Ctrl+B, Alt+Q.

## Palette

`ultron apply` (and so every `ultron theme`) writes the theme's colours to `~/.jocasta/agent/palette.json` when `~/.jocasta/agent` exists: `colors` (`bg-0`…`bg-3`, `fg`, `fg-2`, `fg-3`, `comment`, `blue`, `cyan`, `yellow`, `red`, `green`, `purple`, `orange`) and `ompTheme` (`dark-terminal`, or `light-terminal` for a theme whose `MODE` is light). Jocasta reads it when it starts: restart it after changing the theme.

## Questions, notifications and the bar

- Jocasta writes one JSON line per notification to `~/.local/share/jocasta/data/notifications.jsonl`, questions and Allow requests included. `ultron-attentiond` follows that file: `blocked` becomes a request in the attention queue for the boss window (you are taken there once you stop typing, it gets the urgent mark in focus mode, or it goes to your phone when you are away); `done` and `failed` go to your phone only when you are away.
- The bar's `J` block reads `jocasta status --json` every third tick (about every 6 s): grey `J` when running (`J 2 running` while threads work), red `J ✗` when Jocasta doesn't answer, red `J ● 2 need you` while requests or threads wait.
- mako styles Jocasta's notifications (`app-name=Jocasta`, blue border).

## Pages

Jocasta opens its pages with `xdg-open http://127.0.0.1:<port>/…`. ultron's link router opens local pages in the preview Chromium without moving you: review pages (`/brief/thread-…`, `/brief/pr-…`) on workspace 2, the board (`/board`) on 4, other local pages on 3. Other links go to your browser on 9.

## Keys

Super+B (boss), Super+N (Jocasta's New thread: Ctrl+B then Alt+N), Super+A (attention queue), Super+Shift+S (screenshot path for the boss), Super+Shift+J (friction note).

## Switching the boss

- Away from Jocasta: `ultron agent boss omp` (or any agent, [agents.md](agents.md)), close the boss window (Super+W on workspace 1, confirm) and press Super+B. The bar shows `boss: omp`.
- To Jocasta: `ultron conf set BOSS jocasta && ultron install jocasta` (it runs the first setup when it never ran), then close the boss window and press Super+B.

## Improvement loop

1. **Capture:** press Super+Shift+J whenever Jocasta gets in your way. The note (time, focused window, your text) goes to `~/.local/share/ultron/jocasta-notes.md`.
2. **Triage:** ask the boss "triage my Jocasta notes". It groups the notes and the open review items into issue drafts and shows them to you in one form.
3. **File:** the ones you pick become `gh issue create` issues on `zhivko-kocev/jocasta`, each linking its record, as Jocasta's rules require.
4. **Build:** each issue becomes a Jocasta thread in project `jocasta`, following its AGENTS.md: grill, record, build, `mise run check`, review, then Finish as a merge or a PR according to the repo's `push:` setting.
5. **Ship to yourself:** once a fix is released, quit Jocasta (Ctrl+B, Alt+Q), run `ultron update` in a terminal (mise installs the new release), then press Super+B.
