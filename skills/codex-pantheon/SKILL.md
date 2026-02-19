---
name: pantheon
description: "Orchestrate a pantheon of Claude Code agents (Roman gods) across tmux sessions. Always fresh context, beads viewer integration, parallel building."
---

# Pantheon Orchestration Skill

Deploy and command a group of Claude Code agents named after Roman gods, each running in dedicated tmux sessions with `--dangerously-skip-permissions` for autonomous operation.

## The Pantheon (Build Gods)

| God       | Domain                 | Session Name     | Specialty                          |
|-----------|------------------------|------------------|-----------------------------------|
| Jupiter   | King of Gods           | claude-jupiter   | Architecture, core systems        |
| Mars      | War                    | claude-mars      | Testing, CI/CD, battle-hardening  |
| Vulcan    | Forge                  | claude-vulcan    | Build systems, tooling            |
| Neptune   | Seas                   | claude-neptune   | Data flows, streaming             |
| Apollo    | Light & Arts           | claude-apollo    | UI/UX, frontend, polish           |
| Minerva   | Wisdom                 | claude-minerva   | Documentation, types, contracts   |
| Ceres     | Harvest                | claude-ceres     | Data models, storage, seeds       |
| Diana     | Hunt                   | claude-diana     | Search, discovery, optimization   |

**Note:** Mercury is reserved - use the **Refinery** (session: `claude-refinery`) for git coordination instead of a god named Mercury.

## Core Principles

### 1. Always Fresh Context
Never send follow-up commands without `/clear`. Each task assignment must be self-contained.

**The Safe /clear Process:**
```bash
# ROBUST /clear sequence - prevents pending text/menu issues
tmux send-keys -t claude-jupiter Enter           # 1. Clear any pending input
sleep 1
tmux send-keys -t claude-jupiter Escape Escape   # 2. Cancel any menus/prompts
sleep 1
tmux send-keys -t claude-jupiter "/clear" Enter Enter  # 3. /clear + confirm
sleep 2

# 4. VERIFY /clear worked before sending task
tmux capture-pane -t claude-jupiter -p | tail -5
# Should show fresh prompt, NO "Context left" warning

# 5. Now send new task
tmux send-keys -t claude-jupiter "cd /path/to/project && <full task>" Enter
```

**When to /clear:**
- Before EVERY new task assignment
- When switching to a different bead
- When god goes off-track
- After task completion, before next task
- **NEVER let context drop below 20%** - /clear before it gets there

**When NOT to /clear:**
- Mid-task when working well
- Just to unstick (send Enter only)
- When only checking status (capture-pane)

```bash
# WRONG - builds up stale context
tmux send-keys -t claude-jupiter "fix the bug" Enter

# RIGHT - always fresh with safe process
```

### 2. Use Beads Viewer for Task Discovery
Before assigning work, always check beads:

```bash
# View all beads in project
tmux send-keys -t shell1 "cd /project && bv list" Enter

# Or use bv directly
bv list                    # List issues
bv show <bead-id>         # Full details
bv graph                  # Dependency graph
bv triage                 # AI-suggested priorities
```

### 3. The Claude Command
Always use native install with `--dangerously-skip-permissions` for autonomous operation:

```bash
~/.local/bin/claude --dangerously-skip-permissions
```

**Note:** Use `~/.local/bin/claude` (native install) not `/usr/bin/claude` (npm global) for auto-updates.

## CHROTE Integration

**IMPORTANT:** To make sessions visible in CHROTE, use the CHROTE API and socket:

```bash
# CHROTE tmux socket
CHROTE_SOCKET="/run/tmux/chrote/tmux-1000/default"

# Create session via CHROTE API (makes it visible in CHROTE UI)
curl -s -X POST http://chrote:8080/api/tmux/sessions \
  -H "Content-Type: application/json" \
  -d '{"name": "claude-jupiter"}'

# Send commands using CHROTE's socket
tmux -S $CHROTE_SOCKET send-keys -t claude-jupiter "..." Enter

# Capture output
tmux -S $CHROTE_SOCKET capture-pane -t claude-jupiter -p

# List sessions
tmux -S $CHROTE_SOCKET ls
```

## Spawning the Pantheon

### Create a Single God

```bash
# Create session via CHROTE API
curl -s -X POST http://chrote:8080/api/tmux/sessions \
  -H "Content-Type: application/json" \
  -d '{"name": "claude-jupiter"}'

# Start Claude with permissions bypass (use CHROTE socket)
tmux -S /run/tmux/chrote/tmux-1000/default send-keys -t claude-jupiter \
  "cd /project && ~/.local/bin/claude --dangerously-skip-permissions" Enter
sleep 3

# Verify ready (should see prompt)
tmux -S /run/tmux/chrote/tmux-1000/default capture-pane -t claude-jupiter -p | tail -5
```

### Spawn Multiple Gods at Once

```bash
GODS="jupiter mars mercury vulcan apollo minerva"
for god in $GODS; do
  tmux new-session -d -s "claude-$god" 2>/dev/null || true
  tmux send-keys -t "claude-$god" "claude --dangerously-skip-permissions" Enter
done
sleep 5  # Let them initialize
```

## Assigning Beads

### The Golden Pattern: Fresh Context + Full Task

```bash
# 1. Clear any stale context
tmux send-keys -t claude-mars "/clear" Enter
sleep 1

# 2. Send self-contained task
tmux send-keys -t claude-mars "cd /home/chrote/projects/myapp
Read AGENTS.md if it exists.
Your task: Implement comprehensive test coverage for the auth module.
Bead: auth-tests-001
Commit frequently with bead reference in commit messages." Enter
```

### Batch Assignment Script

```bash
assign_bead() {
  local god=$1
  local project=$2
  local task=$3
  local bead=$4
  
  tmux send-keys -t "claude-$god" "/clear" Enter
  sleep 1
  tmux send-keys -t "claude-$god" "cd $project
Read AGENTS.md if it exists.
$task
Bead: $bead
Commit frequently. Reference bead in commits." Enter
}

# Example usage
assign_bead jupiter /home/chrote/projects/api "Build the REST endpoints" api-endpoints-001
assign_bead apollo /home/chrote/projects/app "Polish the dashboard UI" ui-polish-002
```

## Monitoring the Pantheon

### Quick Status Check

```bash
# See what each god is up to
for god in jupiter mars mercury vulcan apollo minerva; do
  echo "=== $god ==="
  tmux capture-pane -t "claude-$god" -p 2>/dev/null | tail -10
done
```

### Check for Permission Prompts (Shouldn't Happen with --dangerously-skip-permissions)

```bash
# Look for any stuck prompts
for god in jupiter mars mercury vulcan apollo minerva; do
  if tmux capture-pane -t "claude-$god" -p 2>/dev/null | grep -q "Allow\|permission\|Y/n"; then
    echo "⚠️  $god needs attention"
  fi
done
```

### Send Enter to Stuck Agents

```bash
tmux send-keys -t claude-jupiter Enter
```

### View Working Progress

```bash
# Tail a specific god's output
tmux capture-pane -t claude-jupiter -p | tail -30

# Watch in real-time (from another terminal)
watch -n 5 'tmux capture-pane -t claude-jupiter -p | tail -20'
```

## Bead Workflows

### Create a New Bead

```bash
cd /project
bv add "Title of the work item" --priority p2 --type task
```

### Update Bead Status

```bash
bv update <bead-id> --status in-progress
bv update <bead-id> --status done
```

### Close a Bead

```bash
bv close <bead-id> "Resolution message"
```

## Example: Full Orchestration Session

```bash
# 1. Check available beads
cd /home/chrote/projects/myproject
bv list
bv triage  # Get AI suggestions

# 2. Spawn three gods for parallel work
for god in jupiter mars apollo; do
  tmux new-session -d -s "claude-$god" 2>/dev/null
  tmux send-keys -t "claude-$god" "claude --dangerously-skip-permissions" Enter
done
sleep 5

# 3. Assign beads with fresh context
# Jupiter: Core work
tmux send-keys -t claude-jupiter "/clear" Enter && sleep 1
tmux send-keys -t claude-jupiter "cd /home/chrote/projects/myproject
Read AGENTS.md.
Implement the database migration system.
Bead: db-migrate-001
Commit frequently." Enter

# Mars: Testing
tmux send-keys -t claude-mars "/clear" Enter && sleep 1
tmux send-keys -t claude-mars "cd /home/chrote/projects/myproject
Read AGENTS.md.
Write integration tests for the API layer.
Bead: api-tests-002
Commit frequently." Enter

# Apollo: Frontend
tmux send-keys -t claude-apollo "/clear" Enter && sleep 1
tmux send-keys -t claude-apollo "cd /home/chrote/projects/myproject
Read AGENTS.md.
Build the responsive dashboard layout.
Bead: ui-dashboard-003
Commit frequently." Enter

# 4. Monitor progress
watch -n 30 'for g in jupiter mars apollo; do echo "=== $g ==="; tmux capture-pane -t "claude-$g" -p | tail -5; done'
```

## Cleanup

### Kill a Single God

```bash
tmux kill-session -t claude-jupiter
```

### Kill All Gods

```bash
for god in jupiter mars mercury vulcan apollo minerva neptune ceres; do
  tmux kill-session -t "claude-$god" 2>/dev/null
done
```

## The Refinery (Git Coordinator)

When running multiple gods in parallel, **do NOT have them commit individually** - this causes merge conflicts and wastes orchestrator context on git operations.

### ⚠️ CRITICAL RULES

1. **Build gods NEVER commit** - Every task must include "Do NOT commit"
2. **Refinery NEVER auto-polls** - No loops, no timers, no "watch" commands
3. **Orchestrator NEVER does git directly** - Always delegate to Refinery
4. **Refinery is ON-DEMAND ONLY** - Triggered by orchestrator, then idle

### Spawning the Refinery

```bash
CHROTE_SOCKET="/run/tmux/chrote/tmux-1000/default"

# Create session in project directory
tmux -S $CHROTE_SOCKET new-session -d -s claude-refinery -c /path/to/project
tmux -S $CHROTE_SOCKET send-keys -t claude-refinery "~/.local/bin/claude --dangerously-skip-permissions" Enter
sleep 10

# Assign role (NO LOOPS, NO TIMERS)
REFINERY_ROLE='You are the REFINERY - Git Coordinator.

ROLE: Commit code changes on-demand. Nothing else.

WHEN CALLED:
1. git status
2. If changes: review, create commit message, commit
3. Report what you committed
4. Stop and wait

RULES:
- Conventional commits: feat(scope): description
- Do NOT push unless asked
- Do NOT loop or watch - wait for next request
- If conflict: report it, do not auto-resolve

You will be called when needed. Stay idle until then.'

tmux -S $CHROTE_SOCKET send-keys -t claude-refinery "$REFINERY_ROLE" Enter
```

### When to Trigger Refinery

Call the refinery in these situations ONLY:

| Trigger | Command |
|---------|---------|
| God reports "done" | `tmux send-keys -t claude-refinery "Commit any uncommitted changes." Enter` |
| Before assigning new task to a god | Check if their previous work needs committing first |
| During heartbeat | If gods completed work since last check |
| Before clearing a god | Their uncommitted work would be lost context-wise |

### How to Trigger

```bash
# Simple trigger - refinery does one commit cycle then stops
tmux -S $CHROTE_SOCKET send-keys -t claude-refinery "Commit any uncommitted changes." Enter
```

**NEVER send:**
- "Watch for changes"
- "Check every X minutes"  
- "Keep monitoring"
- "Stay active"
- Any form of polling or looping

### Task Template (Mandatory Format)

Every task to a build god MUST include the no-commit rule:

```bash
TASK='<BEAD-ID>: <Title>

PROJECT: /path/to/project
PRD: docs/PRD.md (if exists)

GOAL: <one line>

TASKS:
1. <task>
2. <task>
...

CONSTRAINTS:
- <constraint>
- Do NOT commit - Refinery handles git

DONE WHEN: <acceptance criteria>'

tmux -S $CHROTE_SOCKET send-keys -t claude-<god> "$TASK" Enter
```

### Role Separation (Strictly Enforced)

| Role | Does | Never Does |
|------|------|------------|
| **Build God** | Write code, run tests, verify | Commit, push, git operations |
| **Refinery** | Commit, resolve conflicts | Write code, auto-poll, loop |
| **Orchestrator** | Assign tasks, monitor, trigger refinery | Git operations, write code |

### Why This Matters

1. **No merge conflicts** - One agent commits sequentially
2. **No wasted tokens** - No idle polling loops
3. **Clean history** - Refinery sees full context for good commit messages
4. **Preserved context** - Orchestrator stays focused on coordination

## Heartbeat Checklist

During each heartbeat when orchestrating:

```
□ 1. Check god status (capture-pane for each)
□ 2. For any god showing "done/complete/finished":
     → Trigger refinery: "Commit any uncommitted changes"
     → Wait for refinery to finish
     → Assign next task with /clear
□ 3. For stuck gods: send Enter
□ 4. For off-track gods: /clear and reassign
□ 5. Update memory with progress
```

### Status Check Script

```bash
CHROTE_SOCKET="/run/tmux/chrote/tmux-1000/default"
for god in minerva apollo mars vulcan; do
  echo "=== claude-$god ===" 
  tmux -S $CHROTE_SOCKET capture-pane -t claude-$god -p 2>/dev/null | tail -10
done
```

## Tips

1. **Name commits** - Tell Refinery to prefix commits with bead IDs: `feat(auth): [CMP-001] Add login flow`

2. **Avoid permission drift** - With `--dangerously-skip-permissions`, agents won't ask, but double-check they're working in the right directories

3. **Stagger starts** - When spawning many gods, add small delays to avoid overwhelming the system

4. **Use bv triage** - AI-powered suggestions for what to work on next

5. **Context budget** - Even with /clear, keep task descriptions focused. Too much context = slower agents

6. **Check frequently** - Agents can go off-track. Capture panes every 10-15 minutes during active sessions
