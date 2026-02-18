# Refactoring

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Refactor as described below. Behavior must be unchanged. All tests must pass before and after.

## Goal

{{GOAL}}

## Scope

{{SCOPE}}

## Context Files

{{FILES}}

## Time Budget

- **Target**: ~15 min | **Alert**: 25 min | **Hard stop**: 35 min (decompose into sub-tasks)

## Constraints

- Run tests before refactoring (baseline) and after (verification) — results must match
- Pure structure change only — no features, no bug fixes
- If the refactoring requires breaking changes, report that instead of proceeding
- Delete unused code rather than adding compatibility shims

## Verify

Run the project's test suite (e.g. `pytest`, `npm test`, `cargo test`, `go test ./...`).
Do not commit if test results differ from baseline.

## Report

Provide a final plain-text completion summary:
- **subject**: `Refactoring complete: {{BEAD_ID}}`
- **body**: what changed structurally, test results, commit SHA
