# Changelog

All notable changes to the swarm workspace infrastructure.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

## [2026-02-20] — Relay Skill & Changelog Gate

### Added
- Relay skill doc (`skills/relay/SKILL.md`) covering CLI commands, global flags, agent workflow, spawn usage, data layout, and Go client.
- Mandatory changelog constraint added to all dispatch templates (feature, bug-fix, refactor, custom, script, docs). No changelog entry = no merge.
- Changelog requirement documented in `templates/README.md`.

## [0.5.0] - 2026-02-14

### Changed
- All dispatch templates rewritten — 65% size reduction (950→334 lines)
- ralph.sh inline prompt cut ~77%, language-agnostic test verification
- Removed hardcoded `pytest` from all templates and ralph prompt
- Deleted `templates/CUSTOM_TEMPLATE_DESIGN.md` (design doc, not template)
- Consistent template structure: Objective → Context → Constraints → Verify → Report

## [2026-02-14] — Context Window Cleanup

### Added
- Skills: beads, verify, centurion, bug-scanner, argus, sleep, coding-agent (redirect stub)
- memory/archive.md for historical context
- .trash/ folder for soft deletes

### Changed
- AGENTS.md: slimmed, added swarm cheatsheet
- MEMORY.md: historical content moved to archive
- TOOLS.md: cut redundancy with AGENTS.md
- All bloated skills trimmed 60-70% (code-review, doc-gardener, prompt-optimizer, flywheel-tools, system-audit)

### Removed
- IDENTITY.md (redundant with SOUL.md)
- docs/toolchain.md (content lives in skills now)
- skills/system-status/ (unnecessary wrapper)
- skills/weather/ (not relevant)

## [Unreleased]

### Added
- 2026-02-20: Senate case filing via Relay in `scripts/senate-deliberate.sh` with `--file-case` mode, quick-case support, and JSONL outbox fallback when Relay is unavailable.
- 2026-02-20: Added semantic review scaffolding for Centurion via `scripts/lib/centurion-semantic.sh` and prompt contract at `skills/centurion-review.md`.
- 2026-02-20: Added Centurion pre-commit integration docs at `docs/features/centurion/pre-commit-hook.md` and new `centurion.sh check` command for non-merge quality checks.
- Problem accountability system: `scripts/problem-detected.sh` creates beads for problems, logs to `state/problems.jsonl`, wakes Athena
- E2E test suite: `tests/e2e/` with 4 tests (beads lifecycle, wake gateway, truthsayer scan, dispatch lifecycle) and `run-e2e.sh` runner
- Wake gateway script: `scripts/wake-gateway.sh` uses OpenClaw's `callGateway` from `dist/call-DLNOeLcz.js` for reliable wake signals
- Truthsayer watch integration in `dispatch.sh` for live scanning during agent work

### Changed
- 2026-02-20: `scripts/dispatch.sh` migrated to Relay-first dispatch/completion signaling with `--relay` / `--no-relay` controls, runner heartbeat/register/release hooks, and Relay message fallback to existing status-file/pane detection.
- 2026-02-20: Centurion `merge` now supports quality levels via `--level quick|standard|deep` (default `standard`), with level recorded in result JSON and level-aware gate execution.
- 2026-02-20: Semantic review now performs test-gaming detection (assertion removals, skip markers, and source-only changes) and surfaces `fail`/`review-needed` verdicts with machine-readable flags.
- 2026-02-20: Deep quality-level merges now run semantic review and rollback on `fail` or `review-needed`; added optional `CENTURION_SKIP_TRUTHSAYER=true` toggle for local/CI runs.
- 2026-02-20: Semantic review now emits structured diff-analysis metadata (file/test counts and line deltas) and includes it in prompt context and review result JSON.
- 2026-02-20: Merge conflicts now produce structured conflict reports (file list, marker line numbers, preview snippets) under `extra` in Centurion result JSON.
- 2026-02-20: Added trivial conflict auto-resolution strategies (`ours`/`theirs` for simple stage patterns) with resolution metadata persisted in merge results.
- 2026-02-20: Added Senate escalation protocol for unresolved merge conflicts, writing structured case files to `state/senate-inbox/` and recording escalation metadata in Centurion results.
- 2026-02-20: Added Senate-driven conflict resolution flow that can apply verdict files (`ours`/`theirs` strategies), complete the merge, and persist applied resolution metadata.
- 2026-02-20: Added structured Centurion logging with `debug/info/warn/error` levels plus `--verbose` and `--quiet` merge/status controls.
- 2026-02-20: Added Centurion metrics history logging (`state/centurion-history.jsonl`) and `centurion.sh history --limit N` for recent run inspection.
- 2026-02-20: Added `centurion.sh merge --dry-run` to execute merge checks and report would-merge results without leaving merge commits on `main`.
- `dispatch.sh` uses `wake-gateway.sh` instead of broken `openclaw cron wake` CLI
- `verify.sh` has timeouts (120s npm, 300s cargo/go) and prints test failures instead of silencing them
- All scripts hardened with `set -euo pipefail` and reduced hardcoded paths

### Fixed
- Wake system: `openclaw cron wake` hangs due to WebSocket handshake issues; replaced with direct `callGateway` Node.js call
- Codex dispatch defaults to config model instead of hardcoded o4-mini
- Ralph.sh model validation, pipefail, iteration debug logging

## [0.4.0] - 2026-02-12

### Added
- Overnight orchestrator (`scripts/orchestrator.sh`) with safety guardrails, decision logging, dry-run mode
- Planning layer (`scripts/planner.sh`) for goal decomposition into sequenced tasks
- Calibration system (`scripts/calibrate.sh`) for accept/reject learning
- Git worktree manager (`scripts/worktree-manager.sh`) for parallel agent isolation

## [0.3.0] - 2026-02-12

### Added
- Doc gardening script (`scripts/doc-gardener.sh`) for detecting stale references
- Automatic template selection (`scripts/select-template.sh`) based on task description and historical scores
- Analysis-driven template scoring (`scripts/score-templates.sh`)

## [0.2.0] - 2026-02-12

### Added
- Architecture enforcement linter rules (`scripts/lint-rules/`)
- `verify.sh` integrated as post-completion hook in dispatch
- Custom linter framework (`scripts/lint-agent.sh`) with agent-friendly error messages

## [0.1.0] - 2026-02-12

### Added
- Structured docs directory with `docs/INDEX.md`
- State schema validation (`scripts/validate-state.sh`) wired into dispatch completion
- Run records enriched with `output_summary` and `failure_reason` fields
- Initial dispatch system with tmux-based agent execution
- Bead-based work tracking integration
- JSON state records in `state/runs/` and `state/results/`
- Prompt templates (bug-fix, feature, refactor, docs, script)
- Ralph loop for sequential fresh-session-per-task TDD execution
