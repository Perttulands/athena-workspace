# Overnight Run Pattern

_First documented: 2026-02-19 23:33 EET_

## Overview

This document captures the pattern for autonomous overnight work sessions. The goal: Athena works while Perttu sleeps, producing concrete results by morning.

## The Pattern

```
Evening Setup → PRDs → Strategists → Roadmaps → Beads → Dispatch → Morning Summary
```

### Phase 1: Evening Setup (with Perttu)

1. **Verify infrastructure**
   - Cron jobs point to correct paths
   - HEARTBEAT.md has active work
   - TODO.md is current
   - Relay server running

2. **Align on priorities**
   - What's the big picture?
   - What gets done tonight?
   - What's blocked?

3. **Create PRDs for work**
   - One PRD per subsystem
   - Each PRD defines: purpose, current state, target state, definition of done
   - PRDs must align with system-architecture.md

### Phase 2: Strategic Planning (Opus Agents)

1. **Spawn one strategist per subsystem**
   ```
   sessions_spawn with model=opus, task="analyze PRD, create roadmap"
   ```

2. **Each strategist outputs**
   - Current state summary
   - Target state summary
   - Gap analysis
   - Sequenced task list (each task = potential bead)
   - Recommended first three tasks

3. **Roadmaps saved to** `state/designs/<subsystem>-roadmap.md`

### Phase 3: Bead Creation

1. **Convert roadmap tasks to beads**
   ```bash
   bd create --title "TS-001: Implement Senate verdict" --priority 1
   ```

2. **Tag appropriately**
   - `[truthsayer]`, `[relay]`, etc.
   - Priority based on dependencies

### Phase 4: Dispatch

1. **Work flows through Relay** (target state)
   - Athena sends dispatch message
   - Agent receives, works
   - Agent sends completion message
   - Athena processes result

2. **Current state: dispatch.sh + wake-gateway**
   - Works but not fully Relay-based yet

### Phase 5: Morning Summary

1. **Athena reports**
   - What was completed
   - What's blocked
   - What's next
   - Any issues encountered

2. **Artifacts produced**
   - Updated TODO.md
   - Memory file (memory/YYYY-MM-DD.md)
   - Roadmaps in state/designs/
   - Beads in bd

---

## Current Cron Jobs

| Job | Schedule | Purpose | Model |
|-----|----------|---------|-------|
| `athena-subsystem-work` | 23:00, 02:00, 05:00 | Overnight work sessions | Opus |
| `doc-sync-check` | 06:00 | Documentation drift audit | Sonnet |
| `truthsayer-workspace-scan` | 06:00 | Code quality scan | Sonnet |
| `oathkeeper-scan` | 06:30 | Commitment tracking | Sonnet |
| `learning-loop-daily` | 07:00 | Template scoring | Sonnet |
| `debt-ceiling-check` | 09:00, 15:00, 21:00 | Bead count check | Sonnet |

### Cron Job Details

**athena-subsystem-work** (the main overnight worker):
- Reads TODO.md
- Picks ONE concrete task
- Does the work
- Updates TODO.md
- Writes to memory/
- Announces result

**Morning jobs** (06:00-07:00):
- Run audits and scans
- Produce reports
- Announce issues

**Debt check** (3x daily):
- Counts open beads
- Alerts if threshold exceeded

---

## HEARTBEAT.md Structure

```markdown
# HEARTBEAT.md

## Active Work
See **TODO.md** for detailed task breakdown.

### Check on wake:
- Any dispatched agents completed? Check state/results/
- Any beads stuck open? Run `bd list`
- Any new memory files from other agents?
- Relay running? `pgrep -f "relay serve" || ~/go/bin/relay serve --addr :9292 &`
- Poll Relay inbox: `~/go/bin/relay poll -url http://localhost:9292 athena`

## Status
Last updated: <timestamp>
Current phase: <what's happening>
```

---

## File Locations

| File | Purpose |
|------|---------|
| `HEARTBEAT.md` | Wake checklist (gitignored, local) |
| `TODO.md` | Task tracking (committed) |
| `docs/features/*/PRD.md` | Subsystem PRDs |
| `state/designs/*-roadmap.md` | Strategic roadmaps |
| `state/results/` | Run outputs |
| `state/runs/` | Run records |
| `memory/YYYY-MM-DD.md` | Daily memory files |

---

## Infrastructure Requirements

### Services that must be running:
- OpenClaw gateway (port 18505)
- Relay server (port 9292)

### Commands to verify:
```bash
# Check OpenClaw
curl -s http://localhost:18505/health

# Check Relay
~/go/bin/relay poll -url http://localhost:9292 athena

# Check beads
bd list

# Check Truthsayer
~/go/bin/truthsayer --version
```

---

## What Can Go Wrong

| Issue | Symptom | Fix |
|-------|---------|-----|
| Cron paths wrong | Jobs fail with "not found" | Update cron job payloads |
| Relay not running | Completion messages lost | Start relay: `~/go/bin/relay serve --addr :9292 &` |
| Context too vague | Agent does wrong work | Make cron prompt more specific |
| Blocked on sudo | Can't install systemd | Note in HEARTBEAT.md, skip |
| Model unavailable | Job fails immediately | Check model name in payload |

---

## First Run: 2026-02-19

### Setup completed:
1. ✅ 9 PRDs written and reviewed
2. ✅ 8 Opus strategists spawned
3. ✅ 8 roadmaps produced (125 tasks total)
4. ⏳ Converting to beads
5. ⏳ Dispatching first work

### Learnings to capture tomorrow:
- Did cron jobs fire correctly?
- Did overnight work produce results?
- What broke?
- What needs adjustment?

---

## Evolution

This pattern will evolve. After each overnight run:
1. Note what worked
2. Note what didn't
3. Update this document
4. Adjust cron jobs / prompts as needed

The goal is a reliable, repeatable pattern for autonomous work.
