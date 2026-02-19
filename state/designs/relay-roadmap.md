# Relay Subsystem Roadmap

_Generated: 2026-02-19_

## 1. Current State Summary

**Relay is operational** with core messaging primitives working:

| Component | Status | Notes |
|-----------|--------|-------|
| CLI Commands | ✅ Working | `serve`, `send`, `poll`, `heartbeat`, `agents`, `reserve` |
| HTTP Server | ✅ Working | Port 9292, background process |
| Filesystem Storage | ✅ Working | `flock`-protected writes, atomic reservations |
| Concurrency | ✅ Tested | 20 goroutines × 1000 msgs = 0 lost |
| Test Coverage | ✅ Good | Core 100%, CLI 85.3%, Store 78.2% |

**Location:** `/home/chrote/athena/tools/relay`  
**Repo:** `github.com/Perttulands/relay`

**What exists:**
- Message send/poll works
- Atomic work reservation (`O_CREAT|O_EXCL`)
- Heartbeat tracking
- Agent discovery

**What doesn't exist yet:**
- Systemd service (manual process start)
- Typed message schema with validation
- Subsystem integration (dispatch still uses files + wake-gateway)
- Monitoring/observability

---

## 2. Target State Summary

**Relay as the nervous system** — every inter-agent message flows through Relay:

```
┌─────────┐                    ┌─────────┐
│ Athena  │──[dispatch msg]──▶│  Relay  │──▶ Agent inbox
└─────────┘                    └─────────┘
                                   ▲
┌─────────┐                        │
│  Agent  │──[completion msg]──────┘──▶ Athena inbox
└─────────┘

┌───────────┐
│Oathkeeper │──[alert]──▶ Relay ──▶ Athena
│  Argus    │──[problem]──▶ Relay ──▶ Athena
│  Senate   │──[verdict]──▶ Relay ──▶ relevant system
│Centurion  │──[gate result]──▶ Relay ──▶ Athena
└───────────┘
```

**Target message schema:**
```json
{
  "type": "dispatch|completion|alert|verdict|heartbeat",
  "from": "athena",
  "to": "agent-42",
  "timestamp": "2026-02-19T23:00:00Z",
  "payload": { ... }
}
```

**Target dispatch flow:**
1. Athena sends dispatch message via Relay
2. Agent polls inbox, receives task
3. Agent works
4. Agent sends completion message via Relay
5. Athena polls, receives result, triggers next action

---

## 3. Gap Analysis

| Gap | Current | Target | Impact |
|-----|---------|--------|--------|
| **Process Persistence** | Manual start, dies on reboot | Systemd service with auto-restart | High: Unreliable in production |
| **Dispatch Flow** | `dispatch.sh` writes files + `wake-gateway` | Relay messages trigger dispatch | High: Fragmented system |
| **Completion Flow** | Shell scripts + file signals | Agent sends completion via Relay | High: No unified observability |
| **Message Schema** | Untyped JSON blobs | Typed messages with validation | Medium: Error-prone integration |
| **Schema Validation** | None | JSON Schema or Go struct validation | Medium: Bad messages slip through |
| **Subsystem Wiring** | Only basic usage | All subsystems use Relay | High: Scattered communication |
| **Monitoring** | None | Throughput, queue depth, latency | Medium: Blind operations |
| **Documentation** | README exists | Full API docs + message catalog | Low: Onboarding friction |

**Critical Path:** Systemd → Dispatch Migration → Completion Flow → Subsystem Wiring

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Reliability)

#### RELAY-001: Systemd Service Installation
**Description:** Create and install a systemd user service for Relay so it survives reboots and auto-restarts on failure.

**Dependencies:** None

**Complexity:** S

**Implementation:**
1. Create service file at `~/.config/systemd/user/relay.service`
2. Configure `ExecStart` to run `relay serve --addr :9292`
3. Set `Restart=on-failure` with backoff
4. Enable with `systemctl --user enable relay`
5. Configure `loginctl enable-linger` for user services without login

**Definition of Done:**
- [ ] `systemctl --user status relay` shows active
- [ ] `relay poll test-inbox` works after system reboot
- [ ] Service restarts within 5s after `kill -9`
- [ ] Logs visible via `journalctl --user -u relay`

---

#### RELAY-002: Message Schema Definition
**Description:** Define typed message schema with Go structs and JSON Schema for validation. Create message catalog documenting all types.

**Dependencies:** None

**Complexity:** M

**Implementation:**
1. Create `pkg/schema/messages.go` with typed structs:
   - `DispatchMessage`
   - `CompletionMessage`
   - `AlertMessage`
   - `VerdictMessage`
   - `HeartbeatMessage`
2. Add `Validate()` method to each type
3. Generate JSON Schema from structs
4. Create `docs/message-catalog.md` documenting all types
5. Add validation to `relay send` command

**Definition of Done:**
- [ ] All 5 message types defined with Go structs
- [ ] `relay send --validate` rejects malformed messages
- [ ] JSON Schema files generated in `schema/`
- [ ] Message catalog documented with examples

---

### Phase 2: Dispatch Migration

#### RELAY-003: Dispatch Client Library
**Description:** Create a Go library for dispatching tasks via Relay, replacing file-based dispatch signals.

**Dependencies:** RELAY-002

**Complexity:** M

**Implementation:**
1. Create `pkg/dispatch/client.go` with `Dispatch()` function
2. Accept: agent ID, task type, payload, priority
3. Construct `DispatchMessage` and send via Relay
4. Return message ID for tracking
5. Add timeout and retry logic

**Definition of Done:**
- [ ] `dispatch.Dispatch("agent-42", "merge", payload)` sends to Relay
- [ ] Returns message ID for correlation
- [ ] Handles Relay unavailability gracefully (retry 3x)
- [ ] Unit tests with mock Relay

---

#### RELAY-004: Completion Client Library
**Description:** Create Go library for agents to send completion messages via Relay.

**Dependencies:** RELAY-002

**Complexity:** S

**Implementation:**
1. Create `pkg/dispatch/completion.go` with `Complete()` function
2. Accept: original message ID, result status, output payload
3. Construct `CompletionMessage` referencing original dispatch
4. Send via Relay to dispatcher's inbox

**Definition of Done:**
- [ ] `dispatch.Complete(msgID, "success", result)` sends completion
- [ ] Completion message includes original dispatch ID
- [ ] Athena can poll and receive completion
- [ ] Unit tests verify message correlation

---

#### RELAY-005: dispatch.sh Migration
**Description:** Modify `scripts/dispatch.sh` to send dispatch via Relay instead of file-based signaling.

**Dependencies:** RELAY-003, RELAY-001

**Complexity:** M

**Implementation:**
1. Add `--relay` flag to dispatch.sh (default: on, `--no-relay` for fallback)
2. Replace file-write logic with `relay send --to <agent>`
3. Construct proper DispatchMessage JSON
4. Update wake-gateway to poll Relay instead of watching files
5. Add migration period: support both modes

**Definition of Done:**
- [ ] `dispatch.sh bead-123 repo agent-42 "prompt"` sends via Relay
- [ ] Agent receives message via `relay poll`
- [ ] Fallback to file-based with `--no-relay` flag
- [ ] Zero lost dispatches in 100-dispatch test

---

#### RELAY-006: Agent Completion via Relay
**Description:** Modify agent completion flow to send results via Relay instead of file signals.

**Dependencies:** RELAY-004, RELAY-005

**Complexity:** M

**Implementation:**
1. Update agent completion script to call `relay send --to athena`
2. Construct CompletionMessage with task result
3. Modify Athena's polling to check Relay inbox
4. Update wake-gateway to act on Relay completion messages
5. Deprecate file-based completion signals

**Definition of Done:**
- [ ] Agent sends completion via `relay send`
- [ ] Athena receives completion via `relay poll athena`
- [ ] wake-gateway triggers on Relay messages
- [ ] End-to-end dispatch→work→completion works via Relay

---

### Phase 3: Subsystem Integration

#### RELAY-007: Oathkeeper Integration
**Description:** Wire Oathkeeper to send commitment alerts via Relay.

**Dependencies:** RELAY-002, RELAY-001

**Complexity:** S

**Implementation:**
1. Add Relay client to Oathkeeper
2. On commitment miss/warning, send AlertMessage to Athena
3. Include: commitment ID, deadline, current state, severity

**Definition of Done:**
- [ ] Commitment miss triggers Relay alert
- [ ] Athena receives alert in inbox
- [ ] Alert includes actionable info (commitment ID, deadline)

---

#### RELAY-008: Argus Integration
**Description:** Wire Argus to send problem reports via Relay (with local fallback).

**Dependencies:** RELAY-002, RELAY-001

**Complexity:** S

**Implementation:**
1. Add Relay client to Argus
2. On problem detection, send AlertMessage via Relay
3. Implement fallback: if Relay down, write to local file (Argus must survive Relay failure)
4. Include: problem type, severity, affected component, suggested action

**Definition of Done:**
- [ ] Argus sends problem reports via Relay
- [ ] Fallback to file-based if Relay unavailable
- [ ] Athena receives and can act on reports

---

#### RELAY-009: Senate/Centurion Integration
**Description:** Wire Senate deliberations and Centurion gate verdicts through Relay.

**Dependencies:** RELAY-002, RELAY-001

**Complexity:** M

**Implementation:**
1. Senate: send deliberation requests/responses via Relay
2. Centurion: send gate check requests/verdicts via Relay
3. Use VerdictMessage type for outcomes
4. Implement request-response correlation via message IDs

**Definition of Done:**
- [ ] Senate deliberation flows through Relay
- [ ] Centurion gate verdicts flow through Relay
- [ ] Request-response correlation works
- [ ] All subsystems can participate in deliberation

---

### Phase 4: Observability

#### RELAY-010: Metrics Endpoint
**Description:** Add `/metrics` endpoint to Relay HTTP server exposing Prometheus-compatible metrics.

**Dependencies:** RELAY-001

**Complexity:** M

**Implementation:**
1. Add Prometheus client library
2. Track: messages_sent, messages_polled, queue_depth per inbox, latency_histogram
3. Expose at `/metrics` endpoint
4. Add `relay stats` CLI command for quick overview

**Definition of Done:**
- [ ] `curl localhost:9292/metrics` returns Prometheus format
- [ ] Queue depth per inbox visible
- [ ] Message throughput tracked
- [ ] `relay stats` shows summary

---

#### RELAY-011: Queue Depth Alerting
**Description:** Implement alerting when message queues grow too large (dead consumer detection).

**Dependencies:** RELAY-010

**Complexity:** S

**Implementation:**
1. Add configurable threshold (default: 100 messages)
2. Periodically check queue depths
3. If threshold exceeded, send alert via... Relay (to athena)
4. Include: inbox name, current depth, oldest message age

**Definition of Done:**
- [ ] Alert sent when queue > threshold
- [ ] Athena receives alert with actionable info
- [ ] No false positives during normal operation

---

## 5. Recommended First Three Tasks

### 1. RELAY-001: Systemd Service Installation
**Why first:** Everything else depends on Relay being reliably running. Currently manual process that dies on reboot. This is a 2-hour task that eliminates a major reliability risk.

**Dispatch prompt:**
```
Install systemd user service for Relay. Create ~/.config/systemd/user/relay.service
that runs "relay serve --addr :9292" with Restart=on-failure. Enable with
systemctl --user enable relay. Verify with reboot test. Location: /home/chrote/athena/tools/relay
```

---

### 2. RELAY-002: Message Schema Definition
**Why second:** Clean contracts enable clean integration. Before wiring subsystems, define the message types so everyone speaks the same language. This is foundational for all integration work.

**Dispatch prompt:**
```
Define typed message schema for Relay. Create pkg/schema/messages.go with Go structs:
DispatchMessage, CompletionMessage, AlertMessage, VerdictMessage, HeartbeatMessage.
Each must have: type, from, to, timestamp, payload. Add Validate() method.
Create docs/message-catalog.md with examples. Location: /home/chrote/athena/tools/relay
```

---

### 3. RELAY-003: Dispatch Client Library
**Why third:** After systemd and schema, this enables the dispatch migration. A clean client library makes RELAY-005 (the actual migration) straightforward. This task is self-contained and testable.

**Dispatch prompt:**
```
Create dispatch client library in pkg/dispatch/client.go for Relay. Function
Dispatch(agentID, taskType, payload, priority) constructs DispatchMessage and
sends via Relay HTTP API. Return message ID. Include 3x retry on failure.
Add unit tests with httptest mock. Location: /home/chrote/athena/tools/relay
```

---

## Task Dependency Graph

```
RELAY-001 (systemd) ──┬──▶ RELAY-005 (dispatch.sh migration)
                      │
RELAY-002 (schema) ───┼──▶ RELAY-003 (dispatch lib) ──▶ RELAY-005
                      │
                      ├──▶ RELAY-004 (completion lib) ──▶ RELAY-006 (completion flow)
                      │
                      ├──▶ RELAY-007 (Oathkeeper)
                      │
                      ├──▶ RELAY-008 (Argus)
                      │
                      └──▶ RELAY-009 (Senate/Centurion)

RELAY-001 ──▶ RELAY-010 (metrics) ──▶ RELAY-011 (alerting)
```

---

## Complexity Summary

| Complexity | Count | Tasks |
|------------|-------|-------|
| S (Small) | 4 | RELAY-001, RELAY-004, RELAY-007, RELAY-008, RELAY-011 |
| M (Medium) | 6 | RELAY-002, RELAY-003, RELAY-005, RELAY-006, RELAY-009, RELAY-010 |
| L (Large) | 0 | — |

**Total estimated effort:** ~2-3 weeks for full implementation

---

## Success Metrics

1. **Reliability:** Relay survives reboots, zero manual restarts needed
2. **Migration:** 100% of dispatches flow through Relay (no file-based)
3. **Integration:** All 5 subsystems send/receive via Relay
4. **Observability:** Queue depth and throughput visible in metrics
5. **Zero Loss:** Maintain 0 lost messages under load
