---
name: ultron
description: Use on the ultron PC to show the user something (diff, web page, running terminal), to run anything as root, or for local-model chores.
---

# ultron

This PC runs ultron (Arch + sway). The user works on numbered workspaces; you may open things only on 2 (review), 3 (web) and 4 (watch), and only through the commands below.

## Showing things to the user

1. **A review** (diff, test run, PR): run `ultron show review [--cwd DIR] [--hold] [-- CMD…]`. With no command it opens `hunk diff --watch` in DIR (default: the current folder). Use `--hold` when the command ends and its output must stay visible.
2. **A web page**: run `ultron show web <url>`. `xdg-open` on a localhost URL (`localhost`, `127.0.0.1`, `[::1]`, `0.0.0.0`, `*.localhost`) does the same; other URLs open in the user's Chrome.
3. **A long-running command** (dev server, log tail, test watcher): run `ultron show watch [--cwd DIR] -- CMD…`. The terminal stays open after the command ends.
4. Never open windows any other way, and never switch the user's workspace yourself (no `swaymsg workspace`, no `swaymsg focus`). ultron decides when to move the user.

## Root access

5. Run `sudo <cmd>` normally. The user sees a password popup with the exact command and the folder it runs in. If it is refused or times out (sudo says no password was provided), do not retry in a loop: tell the user what you needed and why.

## Containers

6. Docker is rootless: `docker`, `docker compose` and `docker buildx bake` work. Ports below 1024 can't be bound, and containers have no access to the host's root.

## Local model

7. For cheap, private chores (summaries, commit-message drafts, classification), use `ask "…"` (piped input works: `git diff | ask "summarise"`) or the API at `http://127.0.0.1:11434` with model `qwen3:4b`.

## Notifications

8. To tell the user something on the desktop (and on the phone when they are away), run `ultron notify "<title>" "<body>"`.

## Jocasta notes

9. The user's notes about Jocasta friction are in `~/.local/share/ultron/jocasta-notes.md`. Read them when asked to triage Jocasta notes.
