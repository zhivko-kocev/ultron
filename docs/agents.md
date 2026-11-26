# Agents on ultron

## What "agent-first" means here

- **The boss window.** Workspace 1 holds one agent you talk to all day: the boss. It starts at login; Super+B takes you there.
- **Three agent workspaces.** Agents open windows only on 2 (review: diffs, files, test runs), 3 (web: local pages in a separate preview browser) and 4 (watch: live terminals). They never move you; ultron does, and only when you stop typing for 2 seconds.
- **Attention.** When an agent needs you, ultron brings you to that agent's window (the boss window, or the terminal the agent runs in). In focus mode (Super+M) it marks the window urgent instead. Super+A goes to whatever needs you, Super+Backspace takes you back.
- **Phone alerts.** When you are away (screen locked, or no input for a while), questions and finished work go to your phone instead (after `ultron install net ntfy`).
- **sudo popup.** An agent's `sudo` shows a password popup with the exact command and folder. Your own terminals keep the normal prompt. What this does and doesn't protect you from: [security.md](security.md).
- **Rootless Docker.** Agents can build and run containers without root access to the PC.
- **Local model.** `ask "…"` and `http://127.0.0.1:11434` run a small model on your GPU for cheap, private chores.

Agents learn all of this from one guide: `ultron guide` prints it, and `ultron info --json` tells them about this machine.

## Choosing the boss

```
ultron agent boss claude
```

Then close the boss window (Super+W on workspace 1) and press Super+B. Any command works as the boss (`ultron conf set BOSS "<command>"`); `omp` is the default and ships with ultron.

## Adding agents

```
ultron agent list          # what's known, installed, and the boss
ultron agent add codex
ultron agent remove codex
```

`add` installs the agent with mise (`mise use -g <tool>@latest`), checks it runs, and puts the ultron guide where that agent reads its global instructions:

| Agent | Installed as | Guide written to |
|---|---|---|
| omp | ships with ultron | `~/.agents/skills/ultron` (already there) |
| claude | `npm:@anthropic-ai/claude-code` | `~/.claude/skills/ultron`, a link to `~/.agents/skills/ultron` |
| codex | `npm:@openai/codex` | a block in `~/.codex/AGENTS.md` |
| gemini | `npm:@google/gemini-cli` | a block in `~/.gemini/GEMINI.md` |
| opencode | `npm:opencode-ai` | a block in `~/.config/opencode/AGENTS.md` |

A block is two lines between `<!-- ultron:begin -->` and `<!-- ultron:end -->`; the rest of the file is never touched, and `remove` takes only the block out. A real folder where a link would go is left alone. `remove` also uninstalls the tool, and if the agent was the boss, sets the boss back to omp.

## Running an agent with the safe sudo

```
ultron agent run claude [ARGS…]
```

This starts the agent in your terminal with ultron's sudo first on its PATH, so its `sudo` goes through the popup. It works for any command, not only the registry's. The boss window always runs this way.

## Letting an agent call you

Point the agent's own notifications at ultron:

- `ultron attention --raise "<what it needs>"`: the agent is blocked on you.
- `ultron attention --done "<what finished>"`: a turn or task finished.

The examples below are **examples**: hook formats change, so check them against the agent's current documentation.

**Claude Code**, in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "ultron attention --raise 'Claude Code needs you'" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "ultron attention --done 'Claude Code finished'" }] }
    ]
  }
}
```

**Codex**, in `~/.codex/config.toml` (Codex adds a JSON argument at the end, which ultron ignores):

```toml
notify = ["ultron", "attention", "--done", "Codex finished"]
```

`--raise` brings you to the window the agent runs in: ultron finds it from the process that called the hook, so the same hook works for the boss and for an agent in any other terminal.

## Agents that aren't in the registry

Add a line to `~/.config/ultron/agents.tsv` (tab-separated, same columns as `agents/registry.tsv`; a line there wins over the registry by name):

```
# name	mise-tool	binary	guide
myagent	-	myagent	block:~/.config/myagent/AGENTS.md
```

- `mise-tool`: anything `mise use -g` accepts, or `-` when you install it yourself.
- `guide`: `link:DIR` (DIR becomes a link to the ultron skill), `skills:DIR` (the skill is linked as `DIR/ultron`), `block:FILE` (the ultron block goes into FILE), or `-` (nothing).

Use the file the agent really reads its global instructions from (its docs say which). Then `ultron agent add myagent`, `run` and `boss` work like the built-in ones.
