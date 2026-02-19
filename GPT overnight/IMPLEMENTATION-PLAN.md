# Cross-System Implementation Plan

Date: 2026-02-18  
Owner: perttu (single-operator execution model)  
Scope: all active repos under `/home/perttu` + host services used by Athena stack.

## Objectives

1. Keep one canonical PRD per active feature as source of truth.
2. Keep the runtime stable while refactoring structure and tooling.
3. Reduce drift between docs, code, services, and operational runbooks.
4. Standardize observability, release safety, and failure recovery across repos.

## Systems Covered

- Core control plane: `athena`
- Runtime/service layer: `openclaw-gateway` user service, `athena-web`, `argus`
- Product/service repos: `athena-web`, `argus`, `relay`, `oathkeeper`, `truthsayer`, `learning-loop`, `ludus-magnus`
- Tooling/platform repos: `beads-repo`, `gws-agent-factory`, `meta_skill`, `ai-master-trainer`, `moonshot-research`, `vps-setup`, `Agent_acadmey`

## Current Baseline (to validate during overnight run)

- `athena` on `main`, clean worktree.
- `openclaw-gateway.service` active in user systemd.
- Mixed repo cleanliness exists across non-core repos.
- `bd` and `br` CLIs present; `dolt` presence must be verified each run.
- `mcp-agent-mail` removed from active runtime and should stay removed.

## Phased Plan

## Phase 1 (0-3 days): Stabilize and Remove Unknowns

### 1) Repo Hygiene Sweep

- Create a machine-readable inventory (`repo-status.tsv`) on every long run.
- For each dirty repo, classify each change as:
  - intentional WIP
  - immediate commit
  - archive/delete candidate
- Exit criteria: no ambiguous untracked artifacts in active repos.

### 2) PRD Governance Lock-In

- Enforce one PRD file per active feature: `docs/features/<feature>/PRD.md`.
- Keep beads as execution tracker only; never PRD substitute.
- Add PRD minimum sections gate:
  - Overview and Objectives
  - Target Personas and User Stories
  - Functional Requirements and Scope (must/should/won't)
  - Definition of Done
- Exit criteria: `./scripts/prd-lint.sh --json` returns zero issues.

### 3) Runtime Health Baseline

- Snapshot service status (`openclaw-gateway`, `athena-web`, `argus`) and key ports (`18500`, `9000`, `8765`) on cadence.
- Capture CPU/memory/disk/load to identify steady-state envelope.
- Exit criteria: no unexplained service flaps during 3h run.

## Phase 2 (3-10 days): Standardize Operations

### 4) Service Contracts and Runbooks

- Create/update runbook per service:
  - start/stop/restart commands
  - health endpoint/command
  - log locations
  - known-failure signatures
  - rollback steps
- Keep all runbooks linked from `docs/INDEX.md`.
- Exit criteria: each core service has a tested restart + rollback procedure.

### 5) Toolchain Consolidation (Beads)

- Decide and document canonical CLI path (new beads flow) with exact versions.
- If `br` is target, document hard dependency policy for `dolt`.
- Keep legacy `bd` data readable but prevent mixed operational paths in daily loop.
- Exit criteria: a single "golden path" command set in docs and scripts.

### 6) CI/Lint Guard Placement

- Keep guard insertion aligned with cutovers (never pre-break mainline).
- Standard guard order:
  1. syntax/static lint
  2. PRD/doc drift lint
  3. service integration smoke tests
- Exit criteria: guard fails only on real regressions, not transitional churn.

## Phase 3 (10-30 days): Hardening and Scale-Readiness

### 7) Observability

- Build a single health snapshot report including:
  - service state
  - port reachability
  - repo drift
  - bead queue health
  - doc/PRD drift
- Add thresholds and alert conditions:
  - service down > 5 min
  - disk > 80%
  - PRD/doc lint non-zero on default branch
- Exit criteria: issues appear first in health report, not via surprise breakage.

### 8) Security and Secrets

- Scan for secrets/config drift in all repos.
- Normalize env var contracts and add `.env.example` where missing.
- Ensure service units do not hardcode sensitive values.
- Exit criteria: reproducible local bootstrap without secret leakage in git.

### 9) Release and Recovery

- Write explicit rollback steps per high-risk change type:
  - path refactors
  - service unit changes
  - data/toolchain migrations
- Keep backup retention policy explicit:
  - repo-local migration backups: 30 days
  - home-directory temp backups: immediate cleanup after validation
- Exit criteria: rollback drill completed once for one representative system.

## System-Specific Implementation Tracks

## Athena (`/home/perttu/athena`)

- Keep `AGENTS.md` as map only; detailed rules in docs.
- Keep hidden path guard (`lint-no-hidden-workspace.sh`) in maintenance suite.
- Ensure overnight analyzer output is in `GPT overnight/runs/` and reviewed daily.
- Add analyzer findings triage to daily loop.

Definition of done:

- Green on `prd-lint`, `doc-gardener`, hidden-path lint, e2e service checks.
- No stale references to removed systems (including `mcp-agent-mail`) in active docs.

## OpenClaw Gateway (`openclaw-gateway.service`)

- Validate service unit and launch command resilience after path/toolchain changes.
- Add a minimal restart validation script and capture journal slices in overnight run.

Definition of done:

- clean restart succeeds and health checks pass; logs are inspectable in one command.

## Argus / Relay / Oathkeeper / Truthsayer

- Standardize per-repo checklist:
  - branch/dirty-state guard
  - smoke test command
  - service/API dependency map
  - release note template
- Keep interface contracts documented so cross-repo changes are coordinated.

Definition of done:

- each repo has a documented smoke test and known dependency contract.

## Athena-Web / Learning-Loop / Ludus-Magnus

- Resolve media/artifact drift (`*.bak`, generated assets) and add ignore rules where needed.
- Add quick UI smoke path (startup + one route check) to overnight or daily checks.

Definition of done:

- clean default branch and deterministic build/start behavior.

## Beads Toolchain (`beads-repo`, workspace integration)

- Pin canonical tooling versions and install checks.
- Add a single diagnostic command block to docs:
  - CLI version
  - storage backend status
  - migration state

Definition of done:

- one documented and verified path from issue creation to completion.

## Cross-Cutting Angles and Deliverables

1. Architecture
- Deliverable: one-page dependency map with owner repo per boundary.

2. Reliability
- Deliverable: service SLO + incident checklist for core runtime components.

3. Documentation Quality
- Deliverable: zero critical doc drift and archived deprecated docs under `docs/archive/`.

4. Product Clarity
- Deliverable: all active features have canonical PRDs in required format.

5. Test Strategy
- Deliverable: defined smoke tests per repo + nightly/overnight selection policy.

6. Performance and Cost
- Deliverable: baseline host metrics and process pressure thresholds.

7. Security
- Deliverable: secrets scan cadence + env contract completeness.

8. Change Management
- Deliverable: cutover checklist template with explicit rollback section.

## Execution Cadence (Single-Operator)

- Daily:
  - Review latest overnight summary.
  - Triage top 3 risks and convert to beads.
  - Keep PRD/doc lints green before new feature work.

- Twice weekly:
  - Repo hygiene pass across all active repos.
  - Service restart drill for one core service.

- Weekly:
  - Archive deprecated docs and stale plans.
  - Validate toolchain versions and migration assumptions.

## Risk Register

1. Mixed bead toolchain commands cause silent state divergence.
Mitigation: publish one canonical command path and gate scripts accordingly.

2. Hidden absolute paths re-enter active docs/scripts.
Mitigation: keep lint guard in regular checks and CI.

3. Local-only operational commits get lost.
Mitigation: push high-value infra/docs commits same day.

4. Single-operator overload causes governance drift.
Mitigation: strict daily top-3 triage + PRD gate before execution.

## Immediate Next Actions

1. Run overnight analyzer (`scripts/gpt-overnight-run.sh`) for 3+ hours.
2. Review `final-summary.md` and `improvements.md`.
3. Convert top findings into prioritized beads and update canonical PRDs only where behavior changes.
