---
feature_slug: relay-agent-comms
primary_bead: bd-tbd
status: draft
owner: athena
scope_paths:
  - scripts/dispatch.sh
  - scripts/lib/config.sh
  - config/agents.json
  - scripts/wake-gateway.sh
last_updated: 2026-02-18
source_of_truth: true
---
# PRD: Relay Agent Communications

## Overview & Objectives
Define a communication system for agents that is simple, reliable, and operationally lightweight.

Problem solved:
- Existing agent communication flow is heavy for actual usage patterns.
- Coordination features needed in practice are narrow (message, reservation, wake, liveness).

Strategic goals:
- Preserve reliable coordination while reducing cognitive and operational complexity.
- Keep communication primitives explicit and scriptable from CLI.
- Improve resilience of wake and completion signaling paths.

## Target Personas & User Stories
Personas:
- Athena (coordinator): needs reliable inbox, liveness, and wake semantics.
- Coding agents: need low-friction peer messaging and file reservation primitives.
- Perttu (operator): needs predictable behavior and easier debugging during incidents.

User stories:
- As a coordinator, I want agent completion messages and wake signals to be durable so that tasks are not lost.
- As a coding agent, I want to reserve file scopes so that parallel edits do not collide.
- As an operator, I want communication state to be inspectable from filesystem/CLI so that recovery is straightforward.

## Functional Requirements & Scope
### Must Have
- Agent-to-agent message send/read operations with durable storage semantics.
- File reservation and release operations with conflict detection.
- Agent registration and heartbeat/liveness tracking.
- Wake mechanism for coordinator notification when work completes or needs attention.
- Operational status command summarizing active agents and coordination state.

### Should Have
- Broadcast messaging and lightweight filtering.
- Garbage collection for stale coordination artifacts.
- Structured JSON output modes for automation.

### Won't Have (For Now)
- Rich web UI as a required runtime dependency.
- Broad workflow orchestration logic inside the comms layer.
- Cross-machine distributed consensus for reservations.

## Definition of Done
The feature is done and working when:
- Agents can exchange messages and reserve/release files in normal parallel workflows.
- Coordinator receives completion notifications through the supported wake path.
- Liveness and reservation state can be queried deterministically from CLI.
- Failure modes (conflict, stale reservation, missing recipient) return clear errors.
- Integration docs match implemented behavior and pass governance checks.

## Success Metrics
- Lower coordination-related failure rate during parallel dispatch windows.
- Lower mean time to diagnose communication failures.
- Reduced coordinator context overhead versus previous communication model.

## Out of Scope Implementation Detail
Protocol-level design notes, migration analysis, and implementation sequence are maintained separately in:
- `docs/specs/ralph/relay-agent-comms-execution-spec.md`
- `docs/archive/2026-02/`
