# Athena Workspace

Personal AI agent orchestration workspace. Athena is a swarm coordinator that decomposes work, dispatches coding agents (Claude, Codex), monitors progress, and delivers verified results.

## Quick Start

```bash
# Clone
git clone https://github.com/Perttulands/athena-workspace.git ~/.openclaw/workspace
cd ~/.openclaw/workspace

# Setup (interactive — prompts for hostname, user, etc.)
./setup.sh

# Or non-interactive with env vars
ATHENA_USER=myuser ATHENA_HOME=/home/myuser ATHENA_HOSTNAME=my-vps ./setup.sh
```

## What's Included

| Directory | Contents |
|-----------|----------|
| `scripts/` | Dispatch, verify, centurion, ralph, orchestrator scripts |
| `scripts/lib/` | Shared libraries (common.sh, config.sh, record.sh) |
| `templates/` | Agent prompt templates (feature, bug-fix, refactor, etc.) |
| `skills/` | Modular skill definitions (beads, coding-agents, argus, etc.) |
| `docs/` | Architecture docs, guides, PRDs |
| `tests/` | E2E and unit tests |
| `state/schemas/` | JSON schemas for run/result/plan records |
| `state/designs/` | Design documents |
| `config/` | Agent configuration (generated from .example) |

## What's NOT Included

These are gitignored and stay local:

- **`memory/`** — Daily memory files, personal conversations
- **`state/runs/`, `state/results/`** — Agent output JSON (may contain sensitive data)
- **`state/watch/`** — Runtime status files
- **`.beads/`** — Local work tracking database
- **`TOOLS.md`, `config/agents.json`, `MEMORY.md`** — Environment-specific (generated from `.example` files by `setup.sh`)
- **API keys, tokens, `.env` files** — Never committed
- **`openclaw.json`** — Gateway config with tokens

## Architecture

```
User → Athena (coordinator) → dispatch.sh → tmux session → coding agent
                                                ↓
                                          watcher (background)
                                                ↓
                                     verify.sh → wake-gateway.sh → Athena
```

- **dispatch.sh** — Creates tmux sessions with coding agents, background watchers for completion
- **verify.sh** — Runs lint, tests, truthsayer checks post-agent
- **ralph.sh** — PRD-driven iterative execution (task by task, fresh sessions)
- **centurion.sh** — Test-gated merge to main

## Key Files

- `AGENTS.md` — Entry point, swarm quick reference, rules
- `SOUL.md` — Agent identity and operating principles
- `CLAUDE.md` — Quick reference for reading order
- `IDENTITY.md` — Who Athena is
- `USER.md` — About the human (customize this)
- `VISION.md` — Why we build, the dream, principles

## Customization

After running `setup.sh`:

1. Edit `USER.md` with your own details
2. Edit `MEMORY.md` to add your active projects
3. Configure `~/.openclaw/openclaw.json` for the gateway
4. Set up API keys in your environment
5. Install auxiliary tools: beads (`br`), truthsayer, argus

## License

Private workspace. Not licensed for redistribution.
