---
name: coding-agents
description: Dispatch coding agents via the swarm system. Use for all coding tasks — features, bugs, refactors, reviews.
---

# Coding Agents

All coding work goes through the swarm system. One command dispatches an agent with full lifecycle management.

## Config Source of Truth

`config/agents.json` defines all models, flags, and commands. Scripts read from it — no hardcoded values.

## Dispatch

```bash
cd ~/athena
bd create --title "Description of work" --priority 1
# → outputs bead ID like bd-32d

./scripts/dispatch.sh <bead-id> <repo-path> <agent-type> "<prompt>" [--branch <name>]
# agent-type examples:
#   claude:opus      → Claude with Opus (design, architecture, judgment)
#   claude:sonnet    → Claude with Sonnet
#   claude:haiku     → Claude with Haiku (fast, cheap)
#   codex            → Codex with gpt-5.3-codex (default from config)
# --branch: shared branch for multiple agents on same repo
```

dispatch.sh handles:
- Model resolution from config/agents.json
- Claude runs in agentic mode (tool access) — NOT print mode
- tmux session creation (named `agent-<bead-id>`)
- Coordination context injected (other active agents and overlap-avoidance instructions)
- Run/result records in state/runs/ and state/results/
- Background watcher for completion detection
- Wake callback to Athena on completion

## Agent Selection

- **codex** (gpt-5.3-codex): Default for all implementation — features, bugs, refactors, system tasks.
- **claude:opus**: Design, architecture, research, judgment, soul.
- **claude:sonnet**: Implementation when codex is unavailable.
- **claude:haiku**: Fast, cheap. Good for smaller tasks.

## Ralph Loop (Sequential TDD)

```bash
./scripts/ralph.sh <project-name> <max-iterations> <sleep-seconds> <model>
# Model is REQUIRED — no silent defaults
# Example: ./scripts/ralph.sh athena_web 25 5 opus
```

Ralph reads a PRD, executes tasks one at a time with TDD, runs code review after each.

## Prompt Quality

Self-contained prompts. Include:
- What to build/fix
- Which files matter
- How to verify (test command, expected behavior)
- Constraints

Templates in `templates/` for common patterns (feature, bug-fix, refactor, docs).

## Monitoring

dispatch.sh runs a background watcher. Completion signals arrive via:
1. wake-gateway callback
2. Background watcher → cron wake (guaranteed)

Do not poll. Wait for the signal.

For >2 agents, delegate monitoring to a `sessions_spawn` sub-agent.

## Checking Status

```bash
# All active sessions
tmux -S /tmp/openclaw-coding-agents.sock list-sessions
# Batch status
./scripts/poll-agents.sh
# One agent's output
tmux -S /tmp/openclaw-coding-agents.sock capture-pane -p -J -t "agent-<bead-id>" -S -20
```

## After Completion

```bash
./scripts/verify.sh <bead-id>    # Quality gate
bd close <bead-id>               # Close
```

Failed agents get max 2 retries (fresh session each time). After 2 failures → escalate.

## Parallel Work

Multiple agents share the same directory and branch with dispatch-injected context:
```bash
./scripts/dispatch.sh <bead-a> <repo-path> claude:sonnet "prompt A" --branch feature-x
./scripts/dispatch.sh <bead-b> <repo-path> claude:sonnet "prompt B" --branch feature-x
```

No worktrees. Agents share one repo directory. dispatch.sh injects coordination context (other active agents and overlap warnings) into each agent's prompt automatically.

Agents coordinate by explicitly declaring scope in their first response and avoiding overlapping file edits.
Auto-commit on agent exit ensures work is never lost.
When all agents are done: `./scripts/centurion.sh merge feature-x <repo-path>`
