# Agent Coordination (Shared Directory)

## Overview

Agents share a single repository directory and coordinate via shared run context. No worktrees, no per-agent branches. Multiple agents work the same branch simultaneously.

## Why Shared Directory?

Worktrees added complexity (lifecycle management, cleanup, merge conflicts) without proportional value on an 8GB VPS. Instead:

- Agents work in the same repo directory on a shared branch
- dispatch.sh provides active-agent context in prompts so agents can avoid overlap
- Auto-commit on agent exit ensures work is never lost
- Centurion merges the shared branch to main when all agents are done

## Shared-Directory Coordination

dispatch.sh automatically injects coordination context into prompts when other agents are active on the same repo.

Agents should:
1. Read the active-agent context before editing
2. Pick non-overlapping file scope where possible
3. Pull with rebase before committing
4. Include clear completion summaries so Athena can sequence follow-up work

## Parallel Workflow

```bash
# Create beads
bd create --title "Add feature A" --priority 1   # → bd-abc
bd create --title "Add feature B" --priority 1   # → bd-def

# Dispatch both on same branch
./scripts/dispatch.sh bd-abc /path/repo claude:sonnet "prompt A" --branch feature-x
./scripts/dispatch.sh bd-def /path/repo claude:sonnet "prompt B" --branch feature-x

# Wait for completion signals (background watcher + wake callback)

# Merge when all done
./scripts/centurion.sh merge feature-x /path/repo
```

## Auto-Commit

The runner script traps on exit and runs `git add -A && git commit`. Agent work is never lost even if the agent crashes or times out.

## Conflict Resolution

Since agents share a directory, git conflicts are possible. Mitigations:

1. **Active-agent context** — agents see peers already working on the same repo
2. **Different files** — prompts should direct agents to different parts of the codebase
3. **Sequential commits** — auto-commit captures each agent's work as it finishes
4. **Rebase on pull** — agents pull with rebase before committing

## Legacy

The worktree system (`worktree-manager.sh`) is deprecated. The old system is tagged `v1-worktree-era` in the workspace repo for recovery if needed.
