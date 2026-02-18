# Agent Coordination (Shared Directory)

## Overview

Agents share a single repository directory and coordinate via MCP Agent Mail. No worktrees, no per-agent branches. Multiple agents work the same branch simultaneously.

## Why Shared Directory?

Worktrees added complexity (lifecycle management, cleanup, merge conflicts) without proportional value on an 8GB VPS. Instead:

- Agents work in the same repo directory on a shared branch
- MCP Agent Mail provides advisory file reservations and inter-agent messaging
- Auto-commit on agent exit ensures work is never lost
- Centurion merges the shared branch to main when all agents are done

## MCP Agent Mail Coordination

Agents use Agent Mail (http://127.0.0.1:8765/api/) to:

1. **Register** — announce presence on a project
2. **Reserve files** — advisory locks so agents avoid editing the same files
3. **Send messages** — announce plans, signal completion, coordinate
4. **Check inbox** — read messages from other agents

dispatch.sh automatically injects coordination context into agent prompts when other agents are active on the same repo.

## Parallel Workflow

```bash
# Create beads
bd create --title "Add feature A" --priority 1   # → bd-abc
bd create --title "Add feature B" --priority 1   # → bd-def

# Dispatch both on same branch
./scripts/dispatch.sh bd-abc /path/repo claude:sonnet "prompt A" --branch feature-x
./scripts/dispatch.sh bd-def /path/repo claude:sonnet "prompt B" --branch feature-x

# Wait for completion signals (Agent Mail + background watcher)

# Merge when all done
./scripts/centurion.sh merge feature-x /path/repo
```

## Auto-Commit

The runner script traps on exit and runs `git add -A && git commit`. Agent work is never lost even if the agent crashes or times out.

## Conflict Resolution

Since agents share a directory, git conflicts are possible. Mitigations:

1. **File reservations** — agents claim files via Agent Mail before editing
2. **Different files** — prompts should direct agents to different parts of the codebase
3. **Sequential commits** — auto-commit captures each agent's work as it finishes
4. **Rebase on pull** — agents pull with rebase before committing

## Legacy

The worktree system (`worktree-manager.sh`) is deprecated. The old system is tagged `v1-worktree-era` in the workspace repo for recovery if needed.
