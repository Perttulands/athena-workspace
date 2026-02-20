# Custom Task

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

{{DESCRIPTION}}

## Time Budget

- **Target**: ~10 min | **Alert**: 20 min | **Hard stop**: 30 min (decompose into sub-tasks)

## Context Files

{{FILES}}

If FILES is not specified, use `git status`, file search, or code exploration to find relevant files.

## Constraints

- Read before editing — understand existing code first
- Atomic commits, one logical change per commit
- Stay in scope — do not refactor unrelated code
- If task exceeds 30 min, STOP and propose sub-task decomposition
- Update `CHANGELOG.md` (Keep a Changelog format) — no changelog entry, no merge

## Verify

Run the project's test suite (e.g. `pytest`, `npm test`, `cargo test`, `go test ./...`).
Do not commit if tests fail.

## Report

Provide a final plain-text completion summary:
- **subject**: `Custom task complete: {{BEAD_ID}}`
- **body**: what was done, files changed, test results, commit SHA, time taken

If stopped at time budget, use subject `Custom task CHECKPOINT: {{BEAD_ID}}` and include
progress, remaining work, and decomposition proposal.
