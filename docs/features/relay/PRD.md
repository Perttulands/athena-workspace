# Relay (Hermes) — PRD

_Last updated: 2026-02-19_

## Purpose

Relay is the **nervous system** of the Agora. Every message between agents flows through Relay. Dispatch commands, completion signals, alerts, deliberations — all of it. Without Relay, every agent is deaf and mute.

**One sentence:** Filesystem-backed message broker with zero message loss.

## Why This Exists

Every distributed system has the same dirty secret: messages get lost. RabbitMQ drops one during restart. Kafka loses track during rebalance. Redis pub/sub shrugs and says "at-most-once."

Relay solved it by not being clever. Messages go on the filesystem. Writes are `flock`-protected. Reservations are `O_CREAT|O_EXCL` — atomic create-or-fail. We tested with 20 concurrent goroutines hammering the same inbox. Zero lost.

## Current State

**Working:**
- CLI: `serve`, `send`, `poll`
- HTTP server on port 9292
- Filesystem-backed message storage
- Atomic operations via flock

**Location:** `/home/chrote/athena/tools/relay`

**Repo:** `github.com/Perttulands/relay`

**Server:** Running on `:9292` (background process, needs systemd)

## What Relay Does

1. **Routes messages** between agents (send/poll)
2. **Reserves work** atomically (first agent wins)
3. **Tracks heartbeats** (who's alive)
4. **Discovers agents** (who exists)

## What Relay Does NOT Do

1. **Transform messages** — Relay is a pipe, not a processor
2. **Make decisions** — That's Athena's job
3. **Store long-term state** — Messages are transient
4. **Guarantee ordering** — Per-inbox FIFO, no global order

## Target State

### The Backbone

In the target architecture, **everything flows through Relay**:

```
Athena ──[Relay]──▶ dispatch message ──▶ Agent
Agent  ──[Relay]──▶ completion message ──▶ Athena
Oathkeeper ──[Relay]──▶ commitment alert ──▶ Athena
Senate ──[Relay]──▶ verdict ──▶ relevant system
Argus ──[Relay]──▶ problem report ──▶ Athena
```

Current state: dispatch.sh uses files + wake-gateway. Target: dispatch is a Relay message.

### Message Schema

```json
{
  "type": "dispatch|completion|alert|verdict|heartbeat",
  "from": "athena",
  "to": "agent-42",
  "timestamp": "2026-02-19T23:00:00Z",
  "payload": { ... }
}
```

### Dispatch Flow (Target)

1. Athena sends dispatch message via Relay
2. Agent polls inbox, receives task
3. Agent works
4. Agent sends completion message via Relay
5. Athena polls inbox, receives result
6. Wake triggers next action

### Systemd Integration

Relay must survive reboots:
- User service: `~/.config/systemd/user/relay.service`
- Auto-restart on failure
- Log to journald

## Definition of Done

1. ✅ Core messaging works (send/poll)
2. ✅ HTTP server functional
3. ✅ dispatch.sh sends completion via Relay
4. ⬜ Systemd service installed
5. ⬜ Dispatch flow migrated to Relay (no more file-based)
6. ⬜ All subsystems communicate via Relay
7. ⬜ Message schema documented and validated
8. ⬜ Monitoring: message throughput, queue depth

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Athena** | Primary Relay user. Dispatches work, receives results. |
| **Agents** | Poll Relay for tasks, send completions. |
| **Oathkeeper** | Sends commitment alerts through Relay. |
| **Argus** | Sends problem reports through Relay (but can work without it for resilience). |
| **Senate** | Deliberation messages flow through Relay. |
| **Centurion** | Receives gate requests, sends verdicts via Relay. |

## Next Steps (Priority Order)

1. **Systemd service** — Relay survives reboots
2. **Dispatch migration** — Replace file-based with Relay messages
3. **Schema documentation** — Formalize message types
4. **Subsystem wiring** — Connect Oathkeeper, Argus, Senate
5. **Monitoring** — Throughput metrics, queue depth alerts

## Technical Notes

- **Port:** 9292 (avoid 8080 which is Chrote dashboard)
- **Storage:** Filesystem at runtime, no persistence needed
- **Concurrency:** Safe under heavy load (tested 20 goroutines × 1000 msgs)
- **Dependencies:** None (pure Go, stdlib only)

## Mythology

Named for Hermes — winged sandals, data-light trails, a counter on his belt that reads **0 LOST** and he's insufferably proud of it. He's the only character in the Agora you never see standing still. His satchel is always full. His route is the filesystem instead of Mount Olympus.

Honestly, it's a lateral move.
