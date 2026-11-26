# 3. Showing never moves the user

Date: 2026-11-26. Status: accepted (ultron 0.3.0).

**Context.** In 0.2, `ultron show` opened a window and then jumped the user to it once they stopped typing. With several agents showing diffs, pages and terminals, the user was pulled away from their own work many times an hour, and a single pending-request file meant a second request overwrote the first.

**Decision.** `ultron show` only places the window (as a tab on workspace 2, 3 or 4) and marks its workspace in the bar (`new 2`); it never moves the user. Only an attention request (`ultron attention --raise`) moves them, after the 2-second typing guard, never in focus mode or when away. Requests queue, one file per waiting window under `$XDG_RUNTIME_DIR/ultron/attention/`, oldest first; Super+A walks the queue and, when it is empty, goes to the newest shown window. Windows shown with a tag close by themselves once their folder (a thread's worktree) is gone.

**Rejected: jump on show, as before.** An agent wanting you to see something is not an agent blocked on you; treating both alike made every show an interruption.

**Rejected: a single pending request.** Several agents block at once in practice; the newest one silently hid the others.
