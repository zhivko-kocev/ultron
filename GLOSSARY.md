# Glossary

The words ultron's docs, messages and code use, with one meaning each.

- **Workspace**: one of sway's ten numbered desktops (`1:boss` … `10:sys`). Jocasta's per-project and per-thread tabs are **Jocasta tabs**, never "workspaces".
- **Boss**: the agent window on workspace 1 (setting `BOSS`). With Jocasta, its boss pane.
- **Thread**: one omp session Jocasta runs on its own branch and worktree.
- **Show**: an agent opening a window for the user on workspace 2, 3 or 4 (`ultron show …`). Showing never moves the user; the bar marks the workspace (`new 2`).
- **Attention request**: an agent blocked on the user (`ultron attention --raise`). Requests queue, oldest first; only they move the user (Super+A walks them).
- **Review page**: Jocasta's page for a finished thread or a pull request (Jocasta's code calls it a brief). **Task brief**: the text that starts a thread.
- **Works**: the proof that a change builds, passes its checks and was tried, shown before any finding.
- **Finding / question / opinion**: a proven statement about a change / something asked of its author / unproven taste, at most three.
- **Clean-room run**: a check run in a container that sees only the committed tree.
- **Effects**: SwayFX's corners, shadows and window animations (setting `EFFECTS`).
- **Board**: the live page of running threads on workspace 4.
