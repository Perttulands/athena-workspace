# Orchestrator Guide

## Purpose

The orchestrator is the autonomous overnight operator that makes real decisions, reads state, and executes work unattended. It integrates all swarm components into a single feedback-driven execution loop.

## Commands

### `orchestrator.sh run`

Start autonomous execution loop.

**Options:**
- `--max-hours N`: Maximum runtime in hours (default: 8)
- `--max-tasks N`: Maximum tasks to complete (default: 20)
- `--repo <path>`: Repository path (optional)

**Example:**
```bash
orchestrator.sh run --max-hours 4 --max-tasks 10
```

The orchestrator will:
1. Clean up stale agents from previous runs (detect running status without tmux session)
2. Read state (active agents, pending beads, plans, calibration data)
3. Check calibration patterns (call `calibrate.sh patterns`)
4. For each pending bead or plan task:
   - Check disk space (abort if <200MB)
   - If calibration shows high reject rate → skip, flag for human review
   - Dispatch agent to shared branch (call `dispatch.sh`)
   - Log decision to `orchestrator-log.jsonl`
5. Wait for agent completion (dispatch.sh background watcher handles)
6. On completion:
   - Verification already done by `dispatch.sh`
   - If verification fails → retry (dispatch.sh handles)
7. Periodic maintenance: stale agent cleanup, heartbeat logging, disk space checks
8. Repeat until: max hours, max tasks, no work, stop signal, or 5 consecutive failures

### `orchestrator.sh dry-run`

Show planned actions without executing. Use this to verify orchestrator behavior before real execution.

### `orchestrator.sh status`

Show current orchestrator state:
- Active agents count
- Pending beads count
- Stop sentinel status
- Recent events from log

### `orchestrator.sh stop`

Graceful shutdown: finish current tasks, don't start new ones. Creates sentinel file `state/orchestrator-stop`.

## Safety Guardrails

### Max Concurrent Agents

Default: 4 (configurable via `ORCH_MAX_AGENTS`)

Prevents resource exhaustion. The orchestrator waits when at max capacity. Only counts agents with live tmux sessions (ignores stale records).

### Max Runtime

Default: 8 hours (configurable via `ORCH_MAX_HOURS`)

Prevents runaway overnight operation. Orchestrator stops gracefully when limit reached.

### Max Tasks

Default: 20 tasks per session (configurable via `ORCH_MAX_TASKS`)

Prevents unbounded execution. Allows "finish this sprint" workflows.

### Consecutive Failure Circuit Breaker

Stops after 5 consecutive dispatch failures to prevent infinite retry loops when something is fundamentally broken (e.g., agent binary missing, config corruption).

### Disk Space Monitoring

Checks available disk space every iteration. Stops if <200MB free. Also checked by individual dispatch.sh calls.

### Signal Handling

Handles SIGTERM, SIGINT, SIGHUP by creating the stop sentinel for graceful shutdown. Running agents continue to completion; no new tasks are dispatched.

### Calibration-Based Skipping

If a template/agent category has:
- 3+ calibration judgments
- Reject rate > 50%

→ Skip that category, log reason, flag for human review

This prevents repeatedly dispatching work that will be rejected.

## Decision Logging

All decisions logged to `state/orchestrator-log.jsonl` (append-only JSONL format).

**Event types:**
- `orchestrator_start`: Session start with configuration
- `bead_dispatched`: Agent dispatched for a bead
- `dispatch_failed`: Agent dispatch failed
- `bead_skipped`: Bead skipped due to calibration reject rate
- `stale_agent_cleanup`: Stale agent detected and marked failed
- `heartbeat`: Periodic status (tasks completed, active agents, elapsed time)
- `orchestrator_signal`: SIGTERM/SIGINT/SIGHUP received
- `stop_requested`: Stop command received
- `orchestrator_stop`: Session end with reason
- `orchestrator_complete`: Final summary with runtime

**Example log entries:**
```json
{"ts":"2026-02-12T22:00:00Z","event":"bead_dispatched","bead":"bd-abc","agent":"claude","title":"Fix auth timeout"}
{"ts":"2026-02-12T22:10:00Z","event":"heartbeat","tasks_completed":"3","active":"2","elapsed_hours":"1","iteration":"10"}
{"ts":"2026-02-12T22:15:00Z","event":"stale_agent_cleanup","bead":"bd-xyz","session":"agent-bd-xyz"}
```

## Integration Points

The orchestrator integrates these components:

1. **planner.sh**: Reads plans to get pending tasks
2. **calibrate.sh**: Checks historical accept/reject patterns
3. **dispatch.sh**: Launches agents on shared branch (agents coordinate via MCP Agent Mail)
4. **verify.sh**: Already integrated into dispatch.sh completion
5. **poll-agents.sh**: Can inspect agent status independently (`--json` for machine-readable)

## Autonomous Operation Model

The orchestrator is designed to run unattended overnight:

**Before bed:**
```bash
orchestrator.sh dry-run  # Verify behavior
orchestrator.sh run --max-hours 8  # Start overnight run
```

**Morning:**
```bash
orchestrator.sh status  # Check what happened
tail -20 state/orchestrator-log.jsonl  # Review decisions
```

**Emergency stop:**
```bash
orchestrator.sh stop  # Graceful shutdown
```

## Environment Variables

- `ORCH_MAX_AGENTS`: Max concurrent agents (default: 4)
- `ORCH_MAX_HOURS`: Max runtime in hours (default: 8)
- `ORCH_MAX_TASKS`: Max tasks per session (default: 20)
- `ORCH_AUTO_APPROVE`: Skip approval gate (default: false)
- `DISPATCH_TMUX_SOCKET`: tmux socket path (default: /tmp/openclaw-coding-agents.sock)

**Example:**
```bash
ORCH_MAX_AGENTS=7 ORCH_MAX_HOURS=8 ORCH_AUTO_APPROVE=true orchestrator.sh run --repo /path/to/repo
```
