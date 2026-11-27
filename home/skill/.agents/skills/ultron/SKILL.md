---
name: ultron
description: Use on an ultron PC to show the user something (diff, web page, file, running terminal), to ask for the user's attention, to run anything as root, or for local-model chores.
---

# ultron

This PC runs ultron (Arch + sway). The user works on numbered workspaces; you may open things only on 2 (review), 3 (web) and 4 (watch), and only through the commands below. Run `ultron info --json` to learn the machine: the boss, the browser, the workspace map, the local model, Docker, what waits for the user, and whether they are away or in focus mode.

## Showing things to the user

Showing never moves the user: the window opens as a tab on its workspace, the bar marks that workspace (`new 2`), and the user goes there when they choose (Super+A). If you need them to look or act, also raise attention (item 9).

1. **A review** (diff, test run, PR): `ultron show review [--cwd DIR] [--hold] [-- CMD…]`. With no command it opens `hunk diff --watch` in DIR (default: the current folder). Use `--hold` when the command ends and its output must stay visible.
2. **A web page**: `ultron show web <url> [--ws 2|3|4]`. It opens in a separate preview browser on 3 (or the workspace `--ws` names). `xdg-open` on a localhost URL (`localhost`, `127.0.0.1`, `[::1]`, `0.0.0.0`, `*.localhost`) does the same; other URLs open in the user's browser on 9. Jocasta's review pages and board are its own windows (see Jocasta below), not web pages.
3. **A long-running command** (dev server, log tail, test watcher): `ultron show watch [--cwd DIR] [--title T] -- CMD…` on 4. The terminal stays open after the command ends.
4. **A file**: `ultron show file PATH`. Images, PDF, video, audio, text and JSON open on 2; an HTML file opens like a web page. **Code at a line**: `ultron show code FILE[:LINE[:COL]]` opens it in the editor (Zed, workspace 5).
5. Every `show` prints `opened on workspace N (id ID)`. IDs: `ultron-review-…`, `ultron-watch-…`, `web:<n>`, `con:<n>`, `agent-web:<n>`. `ultron show list` prints `ID<TAB>WORKSPACE<TAB>TAG<TAB>TITLE` for the windows opened this way; `ultron show close ID` closes one, `ultron show close --tag T` all with that tag. Close what you opened once it's no longer useful.
6. **Tags**: every `show` takes `--tag T` (default: `$ULTRON_TAG`, else `$JOCASTA_THREAD`); terminal titles start with `[T]`. A tagged window closes by itself once the folder it was opened from (your worktree) is gone.
7. **Your own browser**: browse headless unless the user must see or act; then open the tab with `headed: true`. A visible tab of a browser you drive (remote debugging on) is moved to workspace 3 and listed as `agent-web:<n>`.
8. Never open windows any other way, and never switch the user's workspace or focus yourself (no `swaymsg workspace`, no `swaymsg focus`).

## Asking for the user

9. When you are blocked on the user (a question, an approval, a choice), run `ultron attention --raise "<what you need>"`: only this moves them. Requests wait in a queue, oldest first (`ultron attention --list`); ultron brings the user to your window once they stop typing, marks it urgent in focus mode, or pushes to their phone when they are away. When something long has finished, run `ultron attention --done "<what finished>"` (a phone push only when they are away). Other desktop or phone notices: `ultron notify "<title>" "<body>"`.

## Root access

10. Run `sudo <cmd>` normally. The user sees a password popup with the exact command and the folder it runs in, once per command (nothing is cached), so put related root work in one script and run that. If it is refused or times out (sudo says no password was provided), do not retry in a loop: tell the user what you needed and why.
11. To install or remove a system package use `ultron pkg install NAME…` / `ultron pkg remove NAME…` (official repos and AUR): it also records the package so a reinstall of the machine brings it back. Languages and runtimes: `ultron dev add TOOL` (no root).

## Containers

12. Docker is rootless: `docker`, `docker compose` and `docker buildx bake` work. Ports below 1024 can't be bound, and containers have no access to the host's root.

## Local model

13. For cheap, private chores (summaries, commit-message drafts, classification), use `ask "…"` (piped input works: `git diff | ask "summarise"`) or the API at `http://127.0.0.1:11434`. The model name and whether local AI is on come from `ultron info`.

## Checking the machine

14. `ultron doctor` is safe to run: it never asks for a password and changes nothing. Use it when something on the system seems broken.

## Jocasta

15. When the boss is Jocasta, the user's notes about its friction are in `~/.local/share/ultron/jocasta-notes.md`.
16. To show the user a plan, a flow, a map or facts as a page (Jocasta 0.2 on), write a brief spec (the section types and limits are in Jocasta's boss manual: `text`, `facts`, `flow`, `map`, `diff`, `list`) and run `jocasta brief open spec.json` (or pipe it to `jocasta brief open -`). It opens a Jocasta window on workspace 2 without moving the user; a bad spec exits 2 with `jocasta: show: <why>`.
