---
feature: athena-web
last_updated: 2026-02-19
status: active
owner: athena
---

# Athena Web (The Loom Room) — PRD

_Last updated: 2026-02-19_

## Purpose

Athena Web is the **dashboard** of the Agora. It visualizes beads, runs, agents, and system status in a web interface. The tapestry view where you stand to see everything at once.

**One sentence:** Web UI for monitoring swarm activity.

## Why This Exists

The Agora generates data: beads, runs, feedback, verdicts. Command line is powerful but not overview-friendly. You need a place to:

1. See all active work at a glance
2. Track agent progress
3. Review run history
4. Monitor system health

## Current State

**Exists but unstable:**
- Node.js service
- Port 9000
- Basic bead display
- Tends to crash

**Location:** `/home/chrote/athena/services/athena-web`

**Repo:** `github.com/Perttulands/athena-web`

**Status:** ⚠️ Service tends to die, needs restart

## What Athena Web Does

1. **Displays beads** — Status, priority, assignment
2. **Shows runs** — History, outcomes, durations
3. **Visualizes progress** — What's active, what's stuck
4. **Provides overview** — System health at a glance

## What Athena Web Does NOT Do

1. **Dispatch work** — That's Athena (CLI/Relay)
2. **Make decisions** — Read-only dashboard
3. **Replace CLI** — Complement, not substitute

## Target State

### Views

| View | Shows |
|------|-------|
| **Tapestry** | All beads, colored by status, sized by priority |
| **Timeline** | Recent runs, outcomes, durations |
| **Agents** | Who's active, what they're working on |
| **Health** | System metrics, service status |

### Real-time Updates

- WebSocket connection for live updates
- Beads change status → view updates
- Run completes → timeline updates

### Mobile-Friendly

- Responsive design
- Works on phone for quick checks

## Definition of Done

1. ✅ Basic service exists
2. ⬜ Service stability (doesn't crash)
3. ⬜ Tapestry view implemented
4. ⬜ Timeline view implemented
5. ⬜ Real-time updates
6. ⬜ Mobile-responsive
7. ⬜ Systemd service reliable

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Beads** | Reads bead state for display |
| **State files** | Reads runs/, results/ for history |
| **Athena** | Athena dispatches, Web displays |

## Next Steps (Priority Order)

1. **Stability** — Fix crashes, reliable systemd
2. **Tapestry view** — Visual bead overview
3. **Timeline view** — Run history
4. **WebSocket** — Real-time updates
5. **Mobile** — Responsive design

## Technical Notes

- **Port:** 9000
- **Stack:** Node.js
- **Data:** Reads from beads CLI, state files
- **Issue:** Memory leak or crash under load

## Mythology

The Loom Room is where Athena weaves. In the myths, she wove tapestries that told stories. In the Agora, the tapestry is the work itself — threads of beads interconnected, colors shifting as status changes.

You walk into the Loom Room to see the whole picture. Not one bead, not one run — the entire fabric of what's happening. The threads that are tight, the ones that are loose, the ones that are about to snap.
