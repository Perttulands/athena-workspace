---
feature_slug: swarm-vision
primary_bead: bd-11t
status: active
owner: athena
scope_paths:
  - scripts/dispatch.sh
  - scripts/verify.sh
  - scripts/orchestrator.sh
  - docs/
last_updated: 2026-02-18
source_of_truth: true
---
# PRD: Autonomous Agentic Coding Factory

## Overview & Objectives
Build an autonomous coding system where Athena coordinates disposable coding agents to deliver verified software changes with minimal human orchestration overhead.

Problem solved:
- Human operators spend too much time manually dispatching, checking, and validating agent work.
- Multi-agent runs drift without shared state, quality gates, and reliable completion signals.

Strategic goals:
- Increase trusted autonomous throughput without increasing operator load.
- Ensure every completion is verifiable, auditable, and recoverable.
- Keep the coordinator available to the human while background work continues.

## Target Personas & User Stories
Personas:
- Perttu (operator): needs reliable delivery and clear status without micromanagement.
- Athena (coordinator): needs deterministic dispatch, monitoring, and quality controls.
- Coding agent (worker): needs clear task context, constraints, and completion protocol.

User stories:
- As a system operator, I want to submit work once and receive verified outcomes so that I do not babysit sessions.
- As a coordinator, I want run state and completion signals to be machine-readable so that I can make fast routing decisions.
- As a coordinator, I want retries and failure reasons captured consistently so that recurring failures can be fixed structurally.
- As a coding agent, I want clear instructions and repository context so that I can complete tasks in a single pass.

## Functional Requirements & Scope
### Must Have
- Dispatch lifecycle with `dispatch.sh`: start agent session, persist run/result records, and trigger wake on completion.
- Verification lifecycle with `verify.sh`: lint/tests/scans summarized into a structured verification payload.
- Quality gate enforcement: failed verification marks run as failed and blocks "done" outcomes.
- Standardized run/result schemas under `state/schemas/` and validation tooling.
- Non-blocking coordinator model: dispatch returns immediately; watcher handles completion asynchronously.
- Retry policy with explicit attempt count and deterministic failure reason recording.

### Should Have
- Orchestrator support for overnight autonomous operation with safety limits.
- Template and run analysis loop to improve dispatch quality over time.
- Cross-run reporting for pass rate, retry rate, and common failure classes.

### Won't Have (For Now)
- Full end-to-end autonomy without human approval boundaries for destructive operations.
- Multi-host distributed dispatch across several machines.
- Runtime decisions based on opaque heuristics without traceable state artifacts.

## Definition of Done
The feature is done and working when:
- Dispatch can run agent tasks end-to-end and produce valid run/result records for each attempt.
- Verification output is consistently attached to outcomes and used in pass/fail decisions.
- Completion and failure paths both wake Athena with actionable context.
- Regression tests for dispatch/verification flows pass.
- Documentation in `docs/` matches current behavior and passes doc governance checks.

## Success Metrics
- Verification pass rate trend improves over time for comparable task categories.
- Mean time from dispatch to verified outcome decreases.
- Percentage of runs requiring manual intervention decreases.
- Coordinator idle-blocking time during active dispatch windows approaches zero.

## Out of Scope Implementation Detail
Task decomposition, sprint checklists, and Ralph execution sequencing are maintained separately in:
- `docs/specs/ralph/swarm-vision-execution-spec.md`
