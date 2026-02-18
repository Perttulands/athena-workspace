---
feature_slug: centurion
primary_bead: bd-601
status: active
owner: athena
scope_paths:
  - scripts/centurion.sh
  - scripts/dispatch.sh
  - scripts/worktree-manager.sh
  - tests/unit/
last_updated: 2026-02-18
source_of_truth: true
---
# PRD: Centurion Merge Gate

## Overview & Objectives
Build a deterministic merge gate that allows agent-produced code to move forward only after required checks pass.

Problem solved:
- Agent branches can accumulate unverified or conflicting changes.
- Manual merge handling creates inconsistent quality standards and hidden risk.

Strategic goals:
- Make merge quality mechanical, not discretionary.
- Reduce integration risk for parallel agent work.
- Provide clear merge status and failure diagnostics.

## Target Personas & User Stories
Personas:
- Perttu (repo owner): needs confidence that merged work is tested and auditable.
- Athena (coordinator): needs a single command to gate and integrate branch work.
- Coding agents: need predictable merge acceptance criteria.

User stories:
- As a repo owner, I want to block merges when tests fail so that broken code never lands on protected branches.
- As a coordinator, I want merge conflicts reported with clear remediation so that retries are fast and targeted.
- As a coordinator, I want status visibility across pending/merged/failed branches so that I can plan next actions.

## Functional Requirements & Scope
### Must Have
- Merge command that attempts branch integration into target branch with explicit conflict handling.
- Test gate execution during merge flow; failing gate prevents successful promotion.
- Rollback or safe abort behavior when merge/test gate fails.
- Status command showing branch merge state and most recent gate outcomes.
- Compatibility with dispatch-generated work branches and shared repository flow.

### Should Have
- Configurable per-repo test commands and timeouts.
- Human-readable and machine-readable status output.
- Integration hooks for wake/alert reporting on failed merge attempts.

### Won't Have (For Now)
- Automatic promotion to release branch without explicit trigger.
- Policy engine for complex conditional merge rules.
- Cross-repo transactional merge orchestration.

## Definition of Done
The feature is done and working when:
- A valid agent work branch can be merged through Centurion when gate checks pass.
- Conflicts and failing gates are reported and do not silently produce partial merges.
- Merge outcomes are observable via a status command.
- Tests covering merge success/failure paths pass.
- Operational docs reflect actual merge-gate behavior.

## Success Metrics
- Reduction in broken merges reaching integration branches.
- Reduced manual merge conflict resolution time.
- High ratio of first-pass gated merges for well-scoped tasks.

## Out of Scope Implementation Detail
Detailed implementation checklist and review gates are maintained separately in:
- `docs/specs/ralph/centurion-execution-spec.md`
