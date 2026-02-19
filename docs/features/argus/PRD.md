---
feature: argus
last_updated: 2026-02-19
status: active
owner: athena
---

# Argus — PRD

_Last updated: 2026-02-19_

## Purpose

Argus is the **watchdog** of the Agora. He monitors infrastructure every 5 minutes, detects problems, takes corrective action, and files beads for issues that need human attention.

**One sentence:** Ops autopilot that fixes things before you wake up.

## Why This Exists

Servers fail. Services crash. Disk fills up. Memory leaks. At 3am, nobody is watching. Argus watches.

He's not just monitoring — he's autonomous. See a dead service? Restart it. See orphan processes eating memory? Kill them. See a pattern of failures? File a bead and alert.

## Current State

**Working:**
- Runs every 5 minutes via systemd timer
- Collectors: disk, memory, services, processes
- Actions: restart services, kill orphans
- Alerts: Telegram notifications
- LLM-powered analysis (Anthropic API)

**Location:** `/home/chrote/athena/tools/argus`

**Repo:** `github.com/Perttulands/argus`

**Service:** `argus.service` + `argus.timer`

## What Argus Does

1. **Collects metrics** — Disk, memory, CPU, service status
2. **Analyzes patterns** — LLM identifies anomalies
3. **Takes action** — Restarts services, kills orphans
4. **Files problems** — Creates beads for issues needing attention
5. **Alerts humans** — Telegram notifications for critical issues

## What Argus Does NOT Do

1. **Code review** — That's Centurion
2. **Track commitments** — That's Oathkeeper
3. **Route messages** — That's Relay
4. **Require Relay** — Argus works out-of-band for resilience

## Target State

### Self-Healing Actions

| Problem | Action |
|---------|--------|
| Service down | Restart (max 3 attempts) |
| Orphan processes | Kill |
| Disk > 90% | Clean temp, alert |
| Memory > 90% | Identify hog, alert |
| Swap thrashing | Alert + identify cause |

### Problem Registry

All detected problems go into `state/problems.jsonl`:
- Timestamp, severity, description
- Action taken (if any)
- Bead created (if any)

### Bead Integration

When Argus detects a problem requiring human attention:
1. Creates bead via `bd create`
2. Tags with `[argus]`
3. Includes diagnostic info

### Independence from Relay

Argus must work even if Relay is down. He's infrastructure. He can't depend on infrastructure he might need to restart.

Optional: Send summaries through Relay when available.

## Definition of Done

1. ✅ Core monitoring works (collectors, analysis)
2. ✅ Actions work (restart, kill)
3. ✅ Alerts work (Telegram)
4. ✅ Systemd service running
5. ⬜ Problem registry implemented
6. ⬜ Bead creation for issues
7. ⬜ Self-healing for common patterns
8. ⬜ Historical analysis (patterns over time)

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Athena** | Can receive Argus summaries (optional). |
| **Relay** | Optional integration. Argus works without it. |
| **Beads** | Argus creates beads for tracked problems. |
| **Telegram** | Primary alert channel. |

## Next Steps (Priority Order)

1. **Problem registry** — Log all detections
2. **Bead creation** — Auto-create beads for issues
3. **Pattern analysis** — Detect recurring problems
4. **Self-healing expansion** — More automatic fixes
5. **Historical dashboard** — Track server health over time

## Technical Notes

- **Timer:** Every 5 minutes
- **Timeout:** Analysis times out at 60 seconds
- **Dependencies:** Anthropic API key, Telegram bot token
- **Resilience:** Works offline (queues alerts)

## Mythology

Argus was Odysseus's dog — faithful, watchful, the only one who recognized his master after twenty years. In the Agora, Argus has one eye that glows red and never closes. He sees the server. He sees the services. He sees the memory leaking at 3am.

He doesn't sleep. He doesn't blink. He doesn't miss.

When something dies on his watch, he brings it back. When something can't be brought back, he files the report and waits at the gate for someone who can.
