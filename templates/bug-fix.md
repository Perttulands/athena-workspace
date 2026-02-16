# Bug Fix

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Fix the bug below. Verify with tests. One atomic commit.

## Bug Description

{{BUG_DESCRIPTION}}

## Expected Behavior

{{EXPECTED_BEHAVIOR}}

## Context Files

{{FILES}}

## Time Budget

- **Target**: ~10 min | **Alert**: 20 min | **Hard stop**: 30 min (decompose into sub-tasks)

## Constraints

- Write a test that reproduces the bug before fixing it
- Do not refactor unrelated code or add features
- If the fix requires architectural changes, report that instead of proceeding

## Verify

Run the project's test suite (e.g. `pytest`, `npm test`, `cargo test`, `go test ./...`).
Do not commit if tests fail.

## Report

Use MCP Agent Mail `send_message` tool to notify completion:
- **subject**: `Bug fix complete: {{BEAD_ID}}`
- **body**: root cause, fix description, test results, commit SHA
