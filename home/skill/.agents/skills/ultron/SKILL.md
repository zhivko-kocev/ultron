---
name: ultron
description: Use on an ultron PC to show the user something (diff, web page, file, running terminal), to ask for the user's attention, to run anything as root, or for local-model chores.
---

# ultron

This PC runs ultron (Arch + sway). The user works on numbered workspaces; you may open things only on 2 (review), 3 (web) and 4 (watch), and only through the commands below. Run `ultron info --json` to learn the machine: the boss, the browser, the workspace map, the local model, Docker, and whether the user is away or in focus mode.

## Showing things to the user

1. **A review** (diff, test run, PR): `ultron show review [--cwd DIR] [--hold] [-- CMD…]`. With no command it opens `hunk diff --watch` in DIR (default: the current folder). Use `--hold` when the command ends and its output must stay visible.
2. **A web page**: `ultron show web <url>`. `xdg-open` on a localhost URL (`localhost`, `127.0.0.1`, `[::1]`, `0.0.0.0`, `*.localhost`) does the same; other URLs open in the user's browser.
3. **A long-running command** (dev server, log tail, test watcher): `ultron show watch [--cwd DIR] [--title T] -- CMD…`. The terminal stays open after the command ends.
4. **A file** (image, PDF, video, audio, text, JSON): `ultron show file PATH`. It opens on workspace 2.
5. Every `show` prints `opened on workspace N (id ID)`. `ultron show list` prints `ID<TAB>WORKSPACE<TAB>TITLE` for the windows opened this way; `ultron show close ID` closes one (`web` closes the preview browser). Close what you opened once it's no longer useful.
6. Never open windows any other way, and never switch the user's workspace or focus yourself (no `swaymsg workspace`, no `swaymsg focus`). ultron decides when to move the user.

## Asking for the user

7. When you are blocked on the user (a question, an approval, a choice), run `ultron attention --raise "<what you need>"`. ultron brings them to your window when they stop typing, marks it urgent in focus mode, or pushes to their phone when they are away.
8. When something long has finished, run `ultron attention --done "<what finished>"` (a phone push only when they are away).
9. Other desktop or phone notices: `ultron notify "<title>" "<body>"`.

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
