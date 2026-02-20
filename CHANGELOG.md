# Changelog

All notable changes to the swarm workspace infrastructure.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

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
- Problem accountability system: `scripts/problem-detected.sh` creates beads for problems, logs to `state/problems.jsonl`, wakes Athena
- E2E test suite: `tests/e2e/` with 4 tests (beads lifecycle, wake gateway, truthsayer scan, dispatch lifecycle) and `run-e2e.sh` runner
- Wake gateway script: `scripts/wake-gateway.sh` uses OpenClaw's `callGateway` from `dist/call-DLNOeLcz.js` for reliable wake signals
- Truthsayer watch integration in `dispatch.sh` for live scanning during agent work

### Changed
- 2026-02-20: `scripts/dispatch.sh` migrated to Relay-first dispatch/completion signaling with `--relay` / `--no-relay` controls, runner heartbeat/register/release hooks, and Relay message fallback to existing status-file/pane detection.
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
