# Wiring nautice to an agent

English · [한국어](agent-setup.ko.md)

`nautice` is **not tied to any agent.** It only makes sounds and banners; when
to call it is up to the agent's configuration. This page is for configuring it
by hand — usually you paste the prompt from [`README.md`](../README.md) into
your agent and it does the rest.

## Two approaches

| | When it fires | Where it goes |
|---|---|---|
| **Hook** | on every matching event, always | the agent's settings file |
| **Tool note** | when the agent decides it is needed | the agent's instructions file |

Hooks never miss but can be noisy; a tool note is quiet but can be forgotten.
They can be combined.

## Hooks — the same everywhere

- **Without `-a` the agent blocks until the sound ends.** Always use it in hooks.
- `-q` suppresses the status line; hook output goes to a log, so use it too.
- On Windows, write `nautice.cmd` instead of `nautice`.
- If you are often away, add `-c both --hold`: the banner stays until dismissed.

To put your agent's name in the spoken text, set `NAUTICE_CALL_MESSAGE`; the
default is neutral ([`cli.md`](cli.md)).

## Example: Claude Code

`~/.claude/settings.json` (or the repository's `.claude/settings.json` for one
project only).

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice call -a -q" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice say -a -q 'Task finished'" }] }
    ]
  }
}
```

`Notification` fires when the agent waits for you (permission request, input);
`Stop` fires when it finishes a turn.

## Other agents

Settings file names and hook events differ per agent, and **each agent knows its
own conventions** — give it the README prompt and it puts things in the right
place. An agent without hooks only gets the instructions-file note.

`AGENTS.md` is the instructions file several agents read; some use their own
name instead, such as `CLAUDE.md`.

```markdown
## Available tools

- `nautice` — a notification CLI that calls the human with sound. Run
  `nautice call -a -q`. It does not fire automatically — use it only when a long
  task finishes or a human decision is needed. `-c both` adds a banner,
  `--hold` keeps it until dismissed.
```

**Stating that it "does not fire automatically"** keeps the agent from calling
it at random moments.
