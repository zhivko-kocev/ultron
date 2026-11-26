# Jocasta on ultron

[Jocasta](https://github.com/zhivko-kocev/jocasta) is the default boss for workspace 1: a terminal program (Rust, ratatui) that runs a boss and many threads, each thread being an omp session. ultron installs it from its releases, starts it at login, and connects it to the desktop. Any other agent can be the boss instead (`omp` ships too); see [agents.md](agents.md).

## Install

mise installs Jocasta from its GitHub releases with the other agent tools (`"github:zhivko-kocev/jocasta" = "latest"` in `/etc/mise/conf.d/ultron-tools.toml`, step `agents`); `ultron update` upgrades it with `mise upgrade` and tells you to restart a running Jocasta when its version changed. omp is not pinned: mise keeps it at the latest release.

The step `ultron install jocasta` (a default step; it does nothing when `BOSS` isn't `jocasta`) needs no root and builds nothing:

1. Checks that `jocasta --version` runs.
2. Runs `jocasta setup --yes` when `~/.jocasta/agent/setup/` holds no markers (setup never ran here). Later setup changes are listed by Jocasta when it starts: run `jocasta setup` to read and apply them.
3. Writes `~/.jocasta/agent/projects.yaml` if missing (roots `~/Projects`, and `~/Work` when it exists, depth 1).
4. Writes the theme's colours to `~/.jocasta/agent/palette.json` (also on every `ultron apply`, e.g. after `ultron theme`; Jocasta reads it when it starts).

To switch to Jocasta from another boss: `ultron conf set BOSS jocasta && ultron install jocasta`, then close the old boss window (Super+W on workspace 1, confirm) and press Super+B.

## How it runs

- sway starts `ultron boss --start` at login. It opens `foot --app-id=ultron-boss` on workspace 1 running `$BOSS` with `~/.local/lib/ultron/agent-bin` first on PATH.
- Closing the boss window stops every thread; they resume on the next start. Super+W asks before closing it.
- Quit Jocasta with Ctrl+B, Alt+Q.

## Integration points

| Piece | What it does |
|---|---|
| Boss window | `foot --app-id=ultron-boss`, with `agent-bin` first on PATH so an agent's `sudo` goes through the popup that shows the command and folder ([security.md](security.md)) |
| `ultron-attentiond` | Follows `~/.local/share/jocasta/data/notifications.jsonl`. `blocked` → a request in the attention queue for the boss window: you are taken there after the typing guard, or it gets the urgent mark in focus mode, or a phone push when away. `done`/`failed` → phone push only when away |
| Link router | `xdg-open http://127.0.0.1:<port>/…` opens in the preview Chromium: review pages (`/brief/thread-…`, `/brief/pr-…`) on workspace 2, the board (`/board`) on 4, other local pages on 3, without moving you; other links go to your browser |
| mako | Styles Jocasta's notifications (`app-name=Jocasta`, blue border) |
| Bar | The `J` block (from `jocasta status --json` every 6 s): grey when running (`J 2 running` while threads work), red `J ✗` when not running, red `J ● 2 need you` while requests or threads wait |
| Keys | Super+B (boss), Super+N (Jocasta's New thread: Ctrl+B then Alt+N), Super+A (attention), Super+Shift+S (screenshot path for the boss), Super+Shift+J (friction note) |
| Colours | `ultron apply` writes the theme into `~/.jocasta/agent/palette.json` (`ompTheme` `dark-terminal` or `light-terminal` by the theme's `MODE`) |

## Fallback: plain omp

If Jocasta doesn't run, `ultron agent boss omp`, close the boss window and press Super+B. The boss is then a plain omp session with the same keys; the bar shows `boss: omp`. `ultron agent boss jocasta` switches back.

## Improvement loop

1. **Capture:** press Super+Shift+J whenever Jocasta gets in your way. The note (time, focused window, your text) goes to `~/.local/share/ultron/jocasta-notes.md`.
2. **Triage:** ask the boss "triage my Jocasta notes". It groups the notes and the open review items into issue drafts and shows them to you in one form.
3. **File:** the ones you pick become `gh issue create` issues on `zhivko-kocev/jocasta`, each linking its record, as Jocasta's rules require.
4. **Build:** each issue becomes a Jocasta thread in project `jocasta`, following its AGENTS.md: grill, record, build, `mise run check`, review, then Finish as a merge or a PR according to the repo's `push:` setting.
5. **Ship to yourself:** once a fix is released, quit Jocasta (Ctrl+B, Alt+Q), run `ultron update` in a terminal (mise installs the new release), then press Super+B.
