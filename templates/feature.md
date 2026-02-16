# Feature Implementation

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Implement the feature below. Add tests. All tests must pass. One atomic commit.

## Specification

{{SPEC}}

## Context Files

{{FILES}}

## Time Budget

- **Target**: ~15 min | **Alert**: 25 min | **Hard stop**: 40 min (decompose into sub-tasks)

## Constraints

- Read relevant files before writing code — understand existing patterns first
- Do not refactor unrelated code or add features beyond the spec
- If changes span multiple subsystems, implement together in one commit
- If the feature is too large for a single session, STOP and propose decomposition
- Follow existing code style and patterns in the repo

## Verify

Run the project's test suite (e.g. `pytest`, `npm test`, `cargo test`, `go test ./...`).
Do not commit if tests fail.

## Report

Use MCP Agent Mail `send_message` tool to notify completion:
- **subject**: `Feature complete: {{BEAD_ID}}`
- **body**: what was added, files changed, test results, commit SHA

If stopped at time budget, use subject `Feature CHECKPOINT: {{BEAD_ID}}` and include
progress, remaining work, and decomposition proposal.
