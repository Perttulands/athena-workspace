# Opus Overnight Analysis -- Athena Workspace

**Date:** 2026-02-18
**Analyst:** Claude Opus 4.6
**Scope:** Exhaustive analysis of every file in `/home/perttu/athena/`
**Files read:** 120+ (every script, doc, config, template, test, skill, schema, site file)
**Methodology:** Read everything first, write findings with exact paths and remediation

---

## Table of Contents

- [A. Deprecated & Stale Content Cleanup](#a-deprecated--stale-content-cleanup)
- [B. Script System Improvements](#b-script-system-improvements)
- [C. Template System](#c-template-system)
- [D. Testing System](#d-testing-system)
- [E. Skills System](#e-skills-system)
- [F. State Management](#f-state-management)
- [G. Configuration](#g-configuration)
- [H. Documentation Architecture](#h-documentation-architecture)
- [I. Security](#i-security)
- [J. Infrastructure & Operations](#j-infrastructure--operations)
- [K. Architectural Improvements](#k-architectural-improvements)
- [L. The Agora Ecosystem](#l-the-agora-ecosystem)
- [M. Developer Experience](#m-developer-experience)
- [N. Performance & Reliability](#n-performance--reliability)
- [O. Future Roadmap Recommendations](#o-future-roadmap-recommendations)

---

## A. Deprecated & Stale Content Cleanup

### A1. The `br` to `bd` Migration -- Comprehensive Audit

The beads CLI was renamed from `br` to `bd`. The docs standard (`/home/perttu/athena/docs/standards/prd-governance.md`) states: "`bd` is the only supported bead CLI." However, `br` references are scattered across 20+ files. This is the single highest-impact cleanup item.

**CRITICAL: Note on the `bd-to-br-migration` skill**

There is a registered skill called `bd-to-br-migration` with the description: "Migrate docs from bd (beads) to br (beads_rust)." This skill's description appears **inverted** -- it describes migrating FROM `bd` TO `br`, which is the wrong direction. The actual migration is FROM `br` TO `bd`. This skill should either be renamed/re-described or removed to avoid confusion.

#### Scripts using `br` instead of `bd`:

| File | Lines | Code |
|------|-------|------|
| `/home/perttu/athena/scripts/problem-detected.sh` | 14 | `br create ...` |
| `/home/perttu/athena/scripts/refine.sh` | 38, 85, 184, 289 | `br create`, `br update`, `br q` |
| `/home/perttu/athena/scripts/orchestrator/common.sh` | 184-199 | `get_pending_beads()` calls `br q --status todo --json` |

**Fix for `problem-detected.sh`:**
```bash
# Line 14: Change
br create --title "$title" --priority "$priority" --label problem --source "problem-detected"
# To:
bd create --title "$title" --priority "$priority" --label problem --source "problem-detected"
```

**Fix for `refine.sh`:**
```bash
# Line 38: br create → bd create
# Line 85: br update → bd update
# Line 184: br update → bd update
# Line 289: br q → bd q
```

**Fix for `orchestrator/common.sh`:**
```bash
# Lines 184-199: Replace all br references with bd in get_pending_beads()
# The function calls: br q --status todo --json
# Should be:          bd q --status todo --json
```

#### Tests using `br` instead of `bd`:

| File | Lines | Issue |
|------|-------|-------|
| `/home/perttu/athena/tests/e2e/helpers.sh` | 117 | `cleanup_test_bead()` calls `br delete` |
| `/home/perttu/athena/tests/e2e/test-dispatch.sh` | 65, 122, 140, 151, 155, 157, 217 | Uses `br` throughout |
| `/home/perttu/athena/tests/e2e/test-dispatch-lifecycle.sh` | 16, 44 | `br delete`, `br q` |
| `/home/perttu/athena/tests/e2e/test-tools.sh` | 37, 69 | Checks for `br` on PATH, tests `br --help` |
| `/home/perttu/athena/tests/e2e/test-beads-lifecycle.sh` | 13, 23, 27, 31, 33 | Uses `br` throughout the lifecycle test |

The `test-tools.sh` issue at line 37 is particularly concerning -- it checks for `br` as a required tool rather than `bd`, meaning the test validates the wrong binary.

#### Skills/docs using `br`:

| File | Lines | Issue |
|------|-------|-------|
| `/home/perttu/athena/skills/code-review/README.md` | 55 | `br update` |
| `/home/perttu/athena/skills/doc-gardener/examples/athena-integration.sh` | 80-98 | `br create`, `br attach` |
| `/home/perttu/athena/state/designs/tdd-dispatch-design.md` | 465 | `br create` |

#### Setup script using `br`:

| File | Lines | Issue |
|------|-------|-------|
| `/home/perttu/athena/setup.sh` | 30 | Checks for `br` in optional tools loop |
| `/home/perttu/athena/setup.sh` | 170 | "Beads CLI (br) -- install from source" |

#### Legacy playbook using `br`:

| File | Lines | Issue |
|------|-------|-------|
| `/home/perttu/athena/docs/archive/2026-02/SWARM-playbook-legacy.md` | 38, 81, 149 | `br create`, `br update`, lists `br` as a tool |

(This is in `/docs/archive/` so it may be intentionally historical, but should have a note.)

#### GPT overnight run script:

| File | Lines | Issue |
|------|-------|-------|
| `/home/perttu/athena/scripts/gpt-overnight-run.sh` | 152-157, 257-259, 283, 317-318 | Checks for `br` presence, captures `br --help` |

**Total: ~60+ individual `br` references across ~20 files need updating to `bd`.**

**Recommended approach:** Create a bead for this migration. Use `sed -i 's/\bbr\b/bd/g'` carefully on each file (manually verify context to avoid false positives like "branch" or "break"). The test files are the highest priority since they validate the wrong binary.

### A2. Stale Worktree References

The worktree model was deprecated. `/home/perttu/athena/scripts/worktree-manager.sh` is now an 8-line stub:
```bash
echo "DEPRECATED: worktree-manager.sh is no longer used." >&2
echo "dispatch.sh now uses shared-directory coordination." >&2
exit 0
```

However, references to the old worktree model persist in:

| File | Issue |
|------|-------|
| `/home/perttu/athena/tests/unit/test_centurion_us001.py` | Tests that `worktree-manager.sh` appears 2+ times in `dispatch.sh` and checks for `WORKTREE_PATH` and `ORIGINAL_REPO_PATH` variables. These tests will FAIL because dispatch.sh no longer contains these references. |
| `/home/perttu/athena/tests/unit/test_centurion_us009.py` | Tests for `worktree-manager.sh destroy` ordering in dispatch.sh completion path. Also will FAIL. |
| `/home/perttu/athena/docs/features/centurion/PRD.md` | `scope_paths` still lists `scripts/worktree-manager.sh` |
| `/home/perttu/athena/docs/specs/ralph/centurion-execution-spec.md` | US-001 is entirely about integrating worktree-manager into dispatch.sh. Extensive worktree references throughout. |
| `/home/perttu/athena/docs/planning-guide.md` | Line 153 mentions "git worktrees" |

**Priority fix:** The two unit tests (`test_centurion_us001.py` and `test_centurion_us009.py`) will cause test failures. They should be either:
1. Rewritten to test the current shared-directory model
2. Deleted if their purpose (worktree integration) is no longer relevant

**Lower priority:** The PRD and execution spec are historical records. Adding a "DEPRECATED" header to the worktree-specific sections would suffice. The `worktree-manager.sh` stub itself can remain as a safety net for any script that might still call it.

### A3. Stale Document References

| File | Issue | Fix |
|------|-------|-----|
| `/home/perttu/athena/state/SCHEMA.md` | References "SWARM.md" which does not exist in the repo | Replace with reference to `docs/architecture.md` or remove |
| `/home/perttu/athena/docs/flywheel.md` | Labels `score-templates.sh` and template auto-selection as "Future" | Both already exist at `/home/perttu/athena/scripts/score-templates.sh` and `/home/perttu/athena/scripts/select-template.sh`. Update labels to "Implemented" |
| `/home/perttu/athena/state/designs/tdd-dispatch-design.md` | Sections 4-5 reference MCP Agent Mail extensively | Add note: "MCP Agent Mail references are historical. See relay PRD for replacement." |

### A4. Dead Code / Deprecated Files

| File | Status | Recommendation |
|------|--------|----------------|
| `/home/perttu/athena/scripts/worktree-manager.sh` | 8-line deprecation stub | Keep as safety net, but add to `.gitignore` tracking note |
| `/home/perttu/athena/skills/coding-agent/SKILL.md` | Deprecated, redirects to `coding-agents` | Delete after confirming no references remain |
| `/home/perttu/athena/bad.go` | 10-line Go file (gitignored) used as Truthsayer test fixture | Already gitignored, fine to keep |

---

## B. Script System Improvements

### B1. `dispatch.sh` -- Core Dispatch Engine

**File:** `/home/perttu/athena/scripts/dispatch.sh` (535 lines)

**Strengths:**
- Well-structured with clear stage separation (preflight, run record, launch, watcher, complete)
- Atomic file writes (tmp + mv pattern)
- Signal handling in runner and watcher (SIGTERM/SIGINT/SIGHUP)
- Disk space monitoring during execution
- Configurable timeouts and retry counts via environment variables
- Auto-commit on agent exit captures work-in-progress

**Improvement opportunities:**

1. **Watcher poll interval should be dynamic.** Currently fixed at 20s (`DISPATCH_WATCH_INTERVAL`). For fast tasks (< 2 minutes), 20s adds unnecessary latency to completion detection. Consider exponential backoff: start at 5s, increase to 20s after 2 minutes, max at 60s after 10 minutes.

2. **Output capture is limited to 500 chars.** The `output_summary` in the run record captures only the last 500 characters of tmux pane output. For agents that produce structured completion reports, this often truncates the useful part. Increase to 2000 chars, or better: capture the last N lines rather than last N chars.

3. **No structured completion contract.** The watcher detects completion via three heuristics (status file, exit code marker, shell prompt). A stronger pattern would be a structured completion file written by the agent: `state/watch/<bead-id>.result.json` with fields like `{status, summary, files_changed, tests_run}`. This would eliminate heuristic detection entirely.

4. **Coordination context is built from state/runs/*.json.** The `build_coordination_context()` function scans all run files to find active agents. On a system with many historical runs, this gets slower. Consider a lightweight `state/active-agents.json` file maintained atomically.

### B2. `verify.sh` -- Post-Completion Quality Gate

**File:** `/home/perttu/athena/scripts/verify.sh` (252 lines)

**Strengths:**
- Runs lint, tests, and Truthsayer scans
- Produces structured verification JSON
- Non-blocking (verification failures are recorded, not blocking)

**Improvements:**

1. **No git diff analysis.** verify.sh checks code quality but does not analyze what changed. Adding `git diff --stat` and `git diff --name-only` to the verification record would give Athena better context for reviewing results.

2. **Truthsayer integration is basic.** Currently runs `truthsayer scan` on the whole repo. Should scan only changed files (`git diff --name-only HEAD~1` as input) for faster feedback and less noise.

3. **UBS (bug scanner) is mentioned in docs but not explicitly called.** The skill at `/home/perttu/athena/skills/bug-scanner/SKILL.md` describes UBS + Truthsayer combined reports, but verify.sh does not call UBS. Wire it in or remove the reference.

### B3. `centurion.sh` -- Merge Gate

**File:** `/home/perttu/athena/scripts/centurion.sh` (185 lines)

**Strengths:**
- Creates develop branch automatically
- Reverts merge on test failure
- Produces structured centurion result JSON
- Configurable test commands and timeouts

**Improvements:**

1. **No pre-merge diff summary.** Centurion merges and tests, but doesn't record what it merged. Adding a diff summary to the centurion result would help Athena understand the scope of changes.

2. **No branch cleanup.** After successful merge to develop, the feature branch is not deleted. Over time this accumulates stale branches. Add `--cleanup` flag to delete merged feature branches.

### B4. `ralph.sh` / `ralphonce.sh` -- PRD Execution Loop

**Files:** `/home/perttu/athena/scripts/ralph.sh` (321 lines), `/home/perttu/athena/scripts/ralphonce.sh` (302 lines)

**Strengths:**
- Sophisticated iteration loop with per-task retry
- Context handoff between iterations via status tracking
- Template-based prompt construction
- Supports both Claude and Codex agents

**Improvements:**

1. **Duplicated logic.** `ralphonce.sh` (single iteration) duplicates ~80% of `ralph.sh` (loop). Extract the shared execution logic into a library function and have both scripts source it.

2. **`refine.sh` uses `br` throughout (see A1).** This is called by ralph for prompt refinement.

### B5. `orchestrator/` -- Autonomous Operation

**Files:** `/home/perttu/athena/scripts/orchestrator/run.sh` (257 lines), `commands.sh` (78 lines), `common.sh` (268 lines)

**Strengths:**
- Safety guardrails: max beads per cycle, max total beads, disk checks
- Structured logging to `state/orchestrator-log.jsonl`
- Command queue for human override (`inbox/incoming/`)
- Graceful shutdown support

**Critical issue:** `common.sh` lines 184-199 use `br` instead of `bd` in `get_pending_beads()`. This function is the core of how the orchestrator finds work. **If `br` is no longer installed, the orchestrator cannot find beads.** This is a potential runtime failure for autonomous overnight operation.

### B6. `gpt-overnight-run.sh` -- Systems Analysis Capture

**File:** `/home/perttu/athena/scripts/gpt-overnight-run.sh` (416 lines)

This is a well-designed periodic systems snapshot tool. It captures systemd services, disk usage, git repo status, PRD lint, doc gardener results, and tooling versions. Produces a structured run directory with snapshots, timeline, manifest, summary, and recommendations.

**Issues:**
- Lines 152-157: Checks for both `bd` and `br` presence. The `br` check should be removed if `br` is fully deprecated.
- Line 16: `HOME_ROOT="${HOME:-/home/perttu}"` -- hardcoded fallback to `/home/perttu`. Use `$HOME` only or fail if unset.

### B7. Other Scripts

**`/home/perttu/athena/scripts/poll-agents.sh`** (157 lines) -- Well-structured agent status dashboard with both JSON and human-readable output modes. Detects stale agents (running in state but no tmux session). No issues found.

**`/home/perttu/athena/scripts/validate-state.sh`** (311 lines) -- Validates run/result JSON files against schema. Has `--fix` mode for legacy records. Solid implementation with clear error messages.

**`/home/perttu/athena/scripts/project-init.sh`** (85 lines) -- Bootstraps new repos with AGENTS.md, CLAUDE.md, and .codex/config.toml. Clean implementation, no issues.

**`/home/perttu/athena/scripts/calibrate.sh`** (411 lines) -- Accept/reject learning system. Records human judgments and correlates with run data. Well-designed with JSON output and structured records.

**`/home/perttu/athena/scripts/planner.sh`** (437 lines) -- Goal decomposition into beads. Uses Claude for planning, produces structured plans in `state/plans/`. Solid implementation.

**`/home/perttu/athena/scripts/analyze-runs.sh`** (336 lines) -- Flywheel analysis tool. Computes success rates, template performance, duration distributions. Good use of jq for data processing.

**`/home/perttu/athena/scripts/score-templates.sh`** (184 lines) -- Template scoring based on run outcomes. Writes scores to `state/template-scores.json`. Clean implementation.

**`/home/perttu/athena/scripts/select-template.sh`** (207 lines) -- Auto-selects best template for a task type based on scores. Falls back to defaults. Well-designed.

---

## C. Template System

### C1. Template Inventory

**Directory:** `/home/perttu/athena/templates/`

| Template | Lines | Purpose |
|----------|-------|---------|
| `feature.md` | ~80 | New feature implementation |
| `bug-fix.md` | ~60 | Bug fix with regression test |
| `refactor.md` | ~70 | Code restructuring |
| `code-review.md` | ~50 | Structured code review |
| `docs.md` | ~40 | Documentation writing |
| `script.md` | ~55 | Shell script implementation |
| `refine.md` | ~45 | Prompt refinement |
| `custom.md` | ~30 | Freeform task |

### C2. Template Quality Assessment

**Strengths:**
- Consistent structure: Objective, Context, Constraints, Acceptance Criteria
- Placeholder variables for customization: `{{REPO_PATH}}`, `{{DESCRIPTION}}`, etc.
- Clear scope boundaries in most templates

**Improvements:**

1. **No verification command in templates.** Templates tell agents what to build but not how to verify. Adding a `## Verification` section with commands to run (e.g., `npm test`, `go test ./...`) would improve first-attempt success rates.

2. **No timeout guidance.** The learning-loop execution spec mentions 19% verification pass rate. Templates should include time budget guidance: "This task should take ~15 minutes. If approaching 30 minutes, stop and report what is blocking you."

3. **No failure recovery instructions.** When an agent encounters a build failure or test failure, templates don't say what to do. Adding "If tests fail, read the error output and fix the root cause. Do not disable or skip tests." would reduce the retry rate.

4. **Template scoring system exists but is not wired into dispatch.** `score-templates.sh` and `select-template.sh` exist and work, but `dispatch.sh` does not call `select-template.sh` automatically. The dispatch flow currently requires the caller to specify the template. Auto-selection should be available as a flag: `dispatch.sh <bead-id> <repo> claude --auto-template "task description"`.

---

## D. Testing System

### D1. E2E Test Suite

**Directory:** `/home/perttu/athena/tests/e2e/`

| Test File | Tests | Status |
|-----------|-------|--------|
| `test-dispatch.sh` | Dispatch flow, run record creation, tmux session | Uses `br` -- **WILL FAIL** |
| `test-dispatch-lifecycle.sh` | Full bead lifecycle through dispatch | Uses `br` -- **WILL FAIL** |
| `test-beads-lifecycle.sh` | Bead create/update/close cycle | Uses `br` -- **WILL FAIL** |
| `test-tools.sh` | Tool availability checks | Checks for `br` -- **WILL FAIL** |
| `test-workspace.sh` | Directory structure validation | Should pass |
| `test-services.sh` | Service health probes | Should pass |
| `test-truthsayer-scan.sh` | Truthsayer JSON output | Should pass |
| `test-argus.sh` | Argus health check | Should pass |
| `test-wake-gateway.sh` | Wake gateway connectivity | Should pass |

**Critical issue:** 4 out of 9 E2E tests use `br` and will fail if `br` is not installed. These tests are the most important to fix because they validate the core dispatch and bead workflows.

**`/home/perttu/athena/tests/e2e/helpers.sh`** (118 lines) -- Assertion library with `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_json_field`. Line 117 uses `br delete` in `cleanup_test_bead()`. Fix: change to `bd delete`.

### D2. Unit Test Suite

**Directory:** `/home/perttu/athena/tests/unit/`

13 pytest files testing centurion functionality:

| Test File | Tests | Issues |
|-----------|-------|--------|
| `test_centurion_us001.py` | Worktree-manager integration in dispatch.sh | **STALE** -- tests for deprecated worktree model. Will FAIL. |
| `test_centurion_us002.py` | centurion.sh script validation | Should pass |
| `test_centurion_us003.py` | Merge creates develop, conflict abort | Should pass |
| `test_centurion_us004.py` | Test gate, merge revert on failure | Should pass |
| `test_centurion_us005.py` | Conflict reporting, wake notification | Should pass |
| `test_centurion_us006.py` | Configured test command priority | Should pass |
| `test_centurion_us007.py` | Status command | Should pass |
| `test_centurion_us007a.py` | Status scoping per repo | Should pass |
| `test_centurion_us008.py` | centurion-promote.sh | Should pass |
| `test_centurion_us008a.py` | Shared test gate library | Should pass |
| `test_centurion_us008b.py` | Shared wake helper library | Should pass |
| `test_centurion_us009.py` | Centurion merge in dispatch including worktree-manager.sh destroy | **STALE** -- tests for worktree-manager. Will FAIL. |
| `test_centurion_us009a.py` | Non-git repo skip | Should pass |

**Priority:** Delete or rewrite `test_centurion_us001.py` and `test_centurion_us009.py`. They test integration points that no longer exist.

### D3. Test Runner

**File:** `/home/perttu/athena/tests/run.sh` (91 lines)

Supports `--e2e`, `--unit`, and `--all` modes. Discovers tests via glob patterns. Reports pass/fail counts.

**Improvements:**
1. No CI integration. The test runner produces human-readable output only. Adding `--junit` or `--json` output mode would enable integration with monitoring dashboards.
2. No test isolation. E2E tests that create beads or tmux sessions can leave artifacts. A test setup/teardown framework would help.

### D4. Test Fixtures

**Directory:** `/home/perttu/athena/tests/fixtures/`

Three prompt fixture files and a README. Minimal but functional. Could be expanded with sample run records and result records for testing validate-state.sh.

---

## E. Skills System

### E1. Skill Inventory

**Directory:** `/home/perttu/athena/skills/`

| Skill | Files | Quality |
|-------|-------|---------|
| `argus/` | SKILL.md | Good -- clear commands, examples |
| `beads/` | SKILL.md | Good -- uses `bd` correctly |
| `bug-scanner/` | SKILL.md | Good -- UBS + Truthsayer combined |
| `centurion/` | SKILL.md | Good -- merge gate docs |
| `code-review/` | SKILL.md, README.md | README uses `br update` (line 55) |
| `coding-agent/` | SKILL.md | **DEPRECATED** -- redirects to coding-agents |
| `coding-agents/` | SKILL.md | Good -- main dispatch skill, uses `bd` |
| `doc-gardener/` | SKILL.md, README.md, QUICKSTART.md, script, tests, examples | Full skill with tests. Example uses `br` |
| `flywheel-tools/` | SKILL.md | Good -- CASS, BV, NTM, RTK, DCG |
| `prompt-optimizer/` | SKILL.md, README.md, 2 scripts, 4 jq filters | Full skill with analysis pipeline |
| `sleep/` | SKILL.md | Good -- graceful context handoff |
| `system-audit/` | SKILL.md | Good -- full system diagnostic |
| `verify/` | SKILL.md | Good -- quality gate docs |

### E2. Skill Quality Issues

1. **`code-review/README.md` line 55:** Uses `br update` instead of `bd update`.

2. **`doc-gardener/examples/athena-integration.sh` lines 80-98:** Uses `br create` and `br attach` instead of `bd` equivalents.

3. **`coding-agent/SKILL.md`:** This deprecated skill should be deleted. It creates confusion: "Did the user mean coding-agent or coding-agents?"

### E3. The Prompt Optimizer -- Hidden Gem

**Directory:** `/home/perttu/athena/skills/prompt-optimizer/`

This is a sophisticated analysis pipeline:
1. `analyze-patterns.sh` (194 lines) -- Detects patterns in run records
2. `optimize-prompts.sh` (112 lines) -- Entry point
3. Four jq filters that group runs, identify issues, generate recommendations, and produce JSON reports

The jq filters at `/home/perttu/athena/skills/prompt-optimizer/jq-filters/` are well-crafted:
- `group-runs.jq` -- Groups runs by template name
- `identify-issues.jq` -- Detects high retry rates, high failure rates, duration outliers, recurring failures
- `generate-recommendations.jq` -- Maps issues to specific template section improvements
- `json-report.jq` -- Produces structured analysis output

**Recommendation:** This tool should be run periodically (weekly) as part of the flywheel. Wire it into the orchestrator or create a systemd timer.

### E4. The Doc Gardener Skill

**Directory:** `/home/perttu/athena/skills/doc-gardener/`

This is the most fully-featured skill with its own script (751 lines), test suite (158 lines, 10 tests), examples, README, and QUICKSTART. It detects stale docs, missing cross-references, and documentation drift.

The standalone script at `/home/perttu/athena/skills/doc-gardener/doc-gardener.sh` is different from and more comprehensive than `/home/perttu/athena/scripts/doc-gardener.sh` (260 lines). Having two different doc-gardener scripts with different capabilities is confusing.

**Recommendation:** Consolidate into one canonical doc-gardener. The skills version is more mature; promote it to replace the scripts version.

---

## F. State Management

### F1. State Directory Structure

```
state/
  runs/          -- Run records (JSON, per bead)
  results/       -- Result records (JSON, per bead)
  watch/         -- Runtime watcher files (status, runner scripts)
  truthsayer/    -- Truthsayer scan results
  archive/       -- Historical run/result records
  calibration/   -- Accept/reject learning records
  plans/         -- Structured execution plans
  verifications/ -- Verification result records
  reviews/       -- Code review records
  designs/       -- Design documents
  schemas/       -- JSON schemas
```

### F2. JSON Schemas

**Directory:** `/home/perttu/athena/state/schemas/`

| Schema | Fields | Issues |
|--------|--------|--------|
| `run.schema.json` | 17 required + 5 nullable | Good coverage, includes verification field |
| `result.schema.json` | 13 required + 2 nullable | Good coverage |
| `calibration.schema.json` | 12 required + 3 nullable | Good -- includes `accepted` boolean and reasoning |
| `plan.schema.json` | 6 required + nested task dependencies | Good -- supports task DAGs |

**Improvement:** The `validate-state.sh` script hardcodes field names rather than referencing the schema files. It should load the schemas dynamically. Currently if you add a field to a schema, you also need to update the validation script.

### F3. State Lifecycle Gaps

1. **No archival automation.** Run and result records accumulate indefinitely. There's a `state/archive/runs/` directory but no script moves old records there. Add a `scripts/archive-state.sh` that moves records older than N days.

2. **No state deduplication.** If dispatch.sh is run twice for the same bead (retry), the second run overwrites the first run record. The first attempt's data is lost. Consider naming run records `<bead-id>-attempt-<N>.json`.

3. **`state/problems.jsonl`** contains a single entry about Athena API being unreachable. This file is written by Argus but nothing in the workspace reads or processes it. Wire it into the orchestrator's decision-making or the dashboard.

---

## G. Configuration

### G1. `config/agents.json`

**File:** `/home/perttu/athena/config/agents.json` (gitignored, generated from example)

The example file at `/home/perttu/athena/config/agents.json.example` uses `{{HOME}}` placeholders correctly. However, the generated file will contain hardcoded `/home/perttu` paths. This is expected for a local config file, but:

**Issue:** If someone clones the repo and runs `setup.sh` with a different username, the paths will be correct. But scripts that reference `$HOME` directly bypass the config. There's a subtle inconsistency: some paths come from `config/agents.json` (resolved by `config.sh`), others are hardcoded in scripts using `$HOME`.

**Fix:** Ensure all scripts use the `paths.sh` library for path resolution rather than `$HOME` directly. The library at `/home/perttu/athena/scripts/lib/paths.sh` already provides canonical path functions.

### G2. Agent Config Schema

The agents.json structure defines:
```json
{
  "agents": {
    "claude": {
      "command": "claude",
      "flags": ["--dangerously-skip-permissions"],
      "models": { "opus": "claude-opus-4-6", "sonnet": "..." },
      "default_model": "opus"
    },
    "codex": {
      "command": "codex",
      "flags": ["exec", "--yolo"],
      "models": { "gpt-5.3-codex": "gpt-5.3-codex" },
      "default_model": "gpt-5.3-codex"
    }
  }
}
```

**Strengths:**
- Model aliases resolve to full names
- Flags are configurable per agent type
- `config.sh` builds complete agent commands from this config

**Improvements:**
1. No schema validation for agents.json itself. Add a `state/schemas/agents.schema.json` and validate during setup.
2. No per-agent timeout configuration. Timeouts are environment variables only (`DISPATCH_WATCH_TIMEOUT`). Allow per-agent-type timeouts in the config.

---

## H. Documentation Architecture

### H1. Entry Points

The documentation has a clear hierarchy:

```
CLAUDE.md          -- Session quick reference (what to read first)
AGENTS.md          -- Swarm rules and dispatch commands
SOUL.md            -- Operating principles (gitignored)
IDENTITY.md        -- Agent identity (gitignored)
```

This is well-designed. `CLAUDE.md` is the entry point that links to everything else. Each session starts by reading it.

### H2. Documentation Inventory

| Directory | Count | Purpose |
|-----------|-------|---------|
| `docs/` | 12 files | Architecture, guides, references |
| `docs/features/` | 4 PRDs | Feature specifications |
| `docs/specs/ralph/` | 4 execution specs | Detailed implementation plans |
| `docs/standards/` | 1 file | PRD governance |
| `docs/research/` | 1 file | Multi-agent architecture research |
| `docs/archive/` | 5 files | Historical documents |

### H3. Documentation Quality Issues

1. **`/home/perttu/athena/docs/flywheel.md`** marks implemented features as "Future." Fix: Update the score-templates and select-template entries to show "Implemented."

2. **`/home/perttu/athena/docs/planning-guide.md`** line 153 mentions "git worktrees." Fix: Update to describe the current shared-directory model.

3. **PRD governance at `/home/perttu/athena/docs/standards/prd-governance.md`** is well-written and authoritative. It correctly states `bd` is the only supported CLI. Good.

4. **Feature PRDs have status inconsistencies:**
   - `/home/perttu/athena/docs/features/centurion/PRD.md` -- scope_paths includes deprecated `worktree-manager.sh`
   - `/home/perttu/athena/docs/features/learning-loop/PRD.md` -- Status: "draft", `primary_bead: bd-tbd` (no bead assigned)
   - `/home/perttu/athena/docs/features/relay-agent-comms/PRD.md` -- Status: "draft", `primary_bead: bd-tbd`
   - `/home/perttu/athena/docs/features/swarm-vision/PRD.md` -- Status: "active" (but execution spec shows all US complete)

5. **No documentation index.** `CLAUDE.md` lists key docs but there's no comprehensive docs index. The `docs-index.sh` script exists but its output is not persisted. Consider generating a `docs/INDEX.md` from it.

### H4. Archive Quality

**Directory:** `/home/perttu/athena/docs/archive/2026-02/`

The archive contains five high-quality analysis documents:

| File | Lines | Quality |
|------|-------|---------|
| `AUDIT-codex-cli.md` | 128 | Excellent -- thorough audit of Codex CLI flags |
| `mcp-agent-mail-analysis.md` | 676 | Excellent -- comprehensive MCP Agent Mail analysis |
| `PLAN-TRUTHSAYER.md` | 165 | Good -- clear build plan with phase structure |
| `REVIEW-agent-comms.md` | 322 | Excellent -- detailed design review with actionable items |
| `SWARM-playbook-legacy.md` | 163 | Historical -- uses `br` throughout (expected for archive) |

The archive docs are well-structured and provide valuable context. The MCP Agent Mail analysis in particular is a thorough reference for understanding the system being replaced by Relay.

---

## I. Security

### I1. Secrets Management

**Positive findings:**
- `.env` files are gitignored
- `*.key`, `*.pem`, `*.secret` are gitignored
- `openclaw.json` (contains credentials) is gitignored
- `config/agents.json` is gitignored (generated from example)
- No API keys or tokens found in any committed file

**Concerns:**

1. **`/home/perttu/athena/scripts/wake-gateway.sh`** (20 lines) calls `callGateway` from the OpenClaw Node.js library. This requires the OpenClaw config at `~/.openclaw/openclaw.json` which contains auth credentials. The script does not validate that the config exists before calling it, which could produce confusing errors.

2. **Agent dispatch uses `--dangerously-skip-permissions` (Claude) and `--yolo` (Codex).** Both flags give agents full shell access. This is intentional and documented, but there's no sandboxing or resource limiting beyond disk space checks. An agent could:
   - Read any file on the system (including other users' data if accessible)
   - Modify system configuration
   - Make network requests
   - Install software

   This is acceptable for a single-user VPS, but the risk should be documented. If the system ever moves to a shared server, this model needs revision.

3. **Truthsayer rule `config-smells.secret-in-config`** detects inline passwords and tokens in code. This is good proactive defense. However, it only runs during verification, not as a pre-commit hook. Consider adding it to the git pre-commit hook.

### I2. File Permissions

The `setup.sh` script makes all `.sh` files executable via `find -exec chmod +x`. This is appropriate. No world-writable files detected in the repo.

### I3. Dependency Security

- No `package-lock.json` committed (gitignored)
- No `node_modules/` committed (gitignored)
- Go binaries (Truthsayer, Relay) are built from source locally
- Python dependencies (pytest) are in `.venv` (gitignored)

No supply chain concerns detected.

---

## J. Infrastructure & Operations

### J1. Service Architecture

From `TOOLS.md.example` and scripts:

| Service | Port | Purpose |
|---------|------|---------|
| openclaw-gateway | 18500 | Agent gateway (OpenClaw) |
| athena-web | 9000 | Dashboard |
| argus | (systemd timer) | Health watchdog |
| mcp-agent-mail | 8765 | Agent coordination (being replaced) |

### J2. Argus Integration

The Argus skill at `/home/perttu/athena/skills/argus/SKILL.md` describes a 5-minute systemd timer that monitors health. The `state/problems.jsonl` file shows Argus has detected issues:

```json
{"ts":"2026-02-18T21:18:37Z","source":"argus","title":"Athena API unreachable at localhost:9000 (connection failed)","details":"Repeated 8x"}
```

This indicates the athena-web service was unreachable 8 times. Argus detects but the workspace has no automation to act on these problems. Wire `state/problems.jsonl` into the orchestrator or wake Athena when critical problems are detected.

### J3. Wake Gateway

**File:** `/home/perttu/athena/scripts/wake-gateway.sh` (20 lines)

Uses Node.js to call OpenClaw's `callGateway` function directly. The comment explains: "the `openclaw cron wake` CLI hangs due to WebSocket handshake issues."

**Issue:** This is a workaround for an OpenClaw bug. If OpenClaw fixes the WebSocket issue, this script should be updated. Add a comment with the OpenClaw issue tracker link or version where this was identified.

### J4. GPT Overnight Run

**File:** `/home/perttu/athena/scripts/gpt-overnight-run.sh` (416 lines)

This is a well-designed operations tool that captures periodic snapshots of system state. It monitors:
- System resources (CPU, memory, disk)
- Service status (systemd units)
- Port availability
- Git repo status across all repos under `$HOME`
- PRD lint and doc gardener results
- Tooling versions

It produces structured artifacts under `GPT overnight/runs/`. The `build_recommendations()` function generates actionable improvement suggestions based on snapshot data.

**Improvements:**
1. The output directory `GPT overnight/runs/` contains a space. This works but is fragile in shell scripts. Consider renaming to `gpt-overnight/runs/`.
2. No alerting. The script captures data but doesn't send alerts. Consider integrating with `wake-gateway.sh` to notify Athena when critical thresholds are crossed.

---

## K. Architectural Improvements

### K1. The Shared-Directory Coordination Model

The current model (post-worktree deprecation) has all agents working in the same directory on the same branch. Coordination relies on:
1. `build_coordination_context()` in dispatch.sh -- scans active runs
2. Prompt instructions telling agents to coordinate
3. Auto-commit on exit captures work

**Strengths:** Simple. No worktree complexity. Works well for 1-2 concurrent agents.

**Weaknesses:**
- Two agents editing the same file will create conflicts
- No lockfile mechanism for file-level coordination
- The prompt-based coordination relies on agent compliance (not enforced)

**Recommendation:** The Relay project (proposed filesystem-based coordination CLI) would address these weaknesses. Prioritize Relay's file reservation feature over its messaging feature.

### K2. The Five-Layer Architecture

From the architecture docs, the system has five layers:

```
Layer 5: Flywheel (analyze-runs, score-templates, calibrate)
Layer 4: Hooks & Templates (templates/, skills/)
Layer 3: State (state/runs/, state/results/, state/schemas/)
Layer 2: Scripts (scripts/dispatch.sh, verify.sh, centurion.sh, etc.)
Layer 1: Tools (bd, tmux, claude, codex, truthsayer, argus)
```

This is a clean architecture. Each layer depends only on layers below it.

**Gap:** There's no explicit interface between layers. Scripts call each other via `source` or subprocess, but there's no contract. A script can reach into any layer. Consider adding a thin API layer (even just documented function signatures) between layers 2 and 3.

### K3. The Flywheel

The flywheel (layer 5) is the most unique aspect of this system. The idea:

```
Work → Records → Analysis → Template Improvement → Better Work
```

Components:
- `analyze-runs.sh` -- Computes metrics from run records
- `score-templates.sh` -- Scores templates by outcome
- `select-template.sh` -- Auto-selects best template
- `calibrate.sh` -- Records human accept/reject judgments
- `prompt-optimizer/` -- Detects patterns and generates recommendations

**Current status:** All components exist and work individually. The loop is not automated end-to-end. The learning-loop execution spec proposes four nested loops (per-run, hourly, daily, weekly) but none are implemented yet.

**Recommendation:** Implement the simplest possible closed loop first:
1. After each run, `analyze-runs.sh` updates metrics
2. `score-templates.sh` updates template scores
3. `select-template.sh` uses scores for next dispatch
4. Weekly: `prompt-optimizer/` generates recommendations for Athena to review

This is achievable with the existing scripts. The more sophisticated loops (hourly refinement, daily strategy) can come later.

### K4. PRD-Driven Development (Ralph)

The Ralph system (`ralph.sh` + execution specs) is a sophisticated PRD-to-code pipeline:
1. PRD defines user stories with acceptance criteria
2. Ralph iterates: pick task, dispatch agent, verify, next task
3. Each iteration produces structured records

The execution specs at `/home/perttu/athena/docs/specs/ralph/` are impressively detailed:
- Centurion spec: 12 user stories, all complete
- Swarm Vision spec: 14 user stories + 4 reviews, all complete
- Learning Loop spec: 4-loop design, comprehensive
- Relay spec: 32 user stories across 4 sprints

**The system works.** The evidence is the codebase itself -- the dispatch system, centurion, verify pipeline, and orchestrator were all built through Ralph iterations.

---

## L. The Agora Ecosystem

### L1. External Tools

| Tool | Repo | Status | Integration |
|------|------|--------|-------------|
| Argus | `~/argus/` | Active | Systemd timer, writes to `state/problems.jsonl` |
| Beads | External CLI | Active | `bd` CLI used throughout |
| Truthsayer | `~/truthsayer/` | Active | Called by verify.sh, 16/22 rules implemented |
| Oathkeeper | External repo | Unknown | Not integrated in workspace scripts |
| Relay | Proposed | Design phase | PRD and execution spec complete |
| Learning Loop | Proposed | Design phase | PRD draft, execution spec complete |
| Athena Web | External repo | Active | Dashboard at port 9000 |
| Ludus Magnus | External repo | Unknown | Not integrated |
| MCP Agent Mail | External | Deprecated | Being replaced by Relay |

### L2. Mythology and Branding

The mythology system at `/home/perttu/athena/mythology.md` (222 lines) is remarkably thorough:
- 6 characters with sigils, 5 defining visual items each, and clear silhouette tests
- 3 places (Agora, Ludus Magnus, Loom Room) with visual descriptions
- 2 symbols (Ouroboros, Beads) with design specs
- Voice guidelines for writing

The forge-site at `/home/perttu/athena/forge-site/` implements this mythology as a polished marketing website:
- `index.html` (429 lines) -- Full landing page with hero, concepts, characters, timeline
- `style.css` (690 lines) -- Custom design system with warm Mediterranean palette
- `script.js` (189 lines) -- Scroll animations, owl easter egg, Konami code
- `IMAGE-PROMPTS.md` (84 lines) -- AI image generation prompts for all characters

The site is well-crafted and on-brand. The CSS uses custom properties for a consistent design system. The JavaScript is clean with IntersectionObserver for scroll animations and clipboard API for code copy.

**Issue:** The site has placeholder images (`needs-art` CSS class). The `IMAGE-PROMPTS.md` provides generation prompts but the images haven't been generated yet.

---

## M. Developer Experience

### M1. Onboarding

**`setup.sh`** (176 lines) provides a good onboarding experience:
1. Checks prerequisites (git, jq, rg, tmux required; go, node, claude, codex, br, gh optional)
2. Gathers configuration interactively (or via env vars)
3. Creates directory structure
4. Generates config files from `.example` templates
5. Makes scripts executable
6. Validates generated JSON

**Issues:**
- Line 30: Checks for `br` as optional tool. Should check for `bd`.
- Line 170: Refers to "Beads CLI (br)". Should say "Beads CLI (bd)".
- No verification step. After setup, there's no "smoke test" to confirm everything works. Add: `./tests/e2e/test-workspace.sh` as a post-setup validation.

### M2. Session Context

The `CLAUDE.md` → `AGENTS.md` → specific skill doc chain provides good session context. Each session starts with `CLAUDE.md` which links to everything needed.

**Improvement:** `CLAUDE.md` could include a "Current System Status" section that shows:
- Active beads count
- Last dispatch time
- Service health summary
This would give the agent immediate situational awareness.

### M3. Skill Discovery

Skills are in `/home/perttu/athena/skills/` with clear `SKILL.md` files. The system prompt includes a skill list with descriptions. This is good.

**Issue:** The `bd-to-br-migration` skill appears to have an inverted description (describes migrating FROM `bd` TO `br`). See note in section A1.

### M4. Error Messages

Scripts generally provide clear error messages. `dispatch.sh` and `centurion.sh` use colored output with `[INFO]`, `[WARN]`, `[ERROR]` prefixes. `setup.sh` uses `ok()`, `warn()`, `fail()` helper functions.

**Improvement:** Some scripts fail silently when commands are not found. For example, `orchestrator/common.sh` calls `br q` which will fail silently if `br` is not installed. Add explicit tool-availability checks before first use.

---

## N. Performance & Reliability

### N1. Dispatch Reliability

**dispatch.sh** has several reliability mechanisms:
- Disk space checks (200MB minimum at preflight, 100MB during execution)
- Timeout enforcement (configurable, default 3600s)
- Signal handling in both runner and watcher
- Atomic file writes (tmp + mv)
- Retry logic (configurable, default 2 retries)

**Potential issues:**

1. **Race condition in watcher.** The watcher polls every 20s. If the agent finishes and the tmux session is cleaned up between polls, the watcher might miss the status file. The runner writes the status file before the session ends, but there's a small window where the session is gone and the status file hasn't been processed yet.

2. **No health check during execution.** The watcher checks if the session is alive and if disk space is sufficient, but doesn't check CPU, memory, or network. An agent consuming all RAM could crash the system before the watcher notices.

3. **Wake-gateway failure is silent.** If `wake-gateway.sh` fails (node not found, OpenClaw down), the completion signal is lost. Athena won't know the agent finished until the next manual check. Add a retry mechanism or write a wake-failure file.

### N2. Concurrency Limits

- `DISPATCH_MAX_RETRIES`: 2 (configurable)
- `DISPATCH_WATCH_TIMEOUT`: 3600s (configurable)
- `ORCHESTRATOR_MAX_CONCURRENT`: not explicitly set, but the orchestrator processes beads sequentially
- Tmux session limit: theoretically unlimited, practically limited by RAM

**Recommendation:** Add a system-wide concurrency limit. Before dispatching a new agent, check `poll-agents.sh --json` for running agent count. If above threshold (e.g., 4), queue the bead.

### N3. Data Durability

- Run/result records are written atomically (tmp + mv)
- Auto-commit on agent exit captures git changes
- No backup mechanism for state files

**Recommendation:** Add `state/` to a periodic backup. Even `cp -r state/ state.bak.$(date +%Y%m%d)` in a cron job would prevent data loss.

---

## O. Future Roadmap Recommendations

### O1. Immediate Priorities (This Week)

1. **Fix `br` → `bd` migration.** 60+ references across 20+ files. Priority order:
   - `scripts/orchestrator/common.sh` (blocks autonomous operation)
   - `scripts/problem-detected.sh`, `scripts/refine.sh` (blocks core workflows)
   - `tests/e2e/` (4 tests will fail)
   - `tests/unit/` (2 stale worktree tests)
   - Everything else

2. **Fix stale unit tests.** `test_centurion_us001.py` and `test_centurion_us009.py` test worktree integration that no longer exists.

3. **Update `setup.sh`** to reference `bd` instead of `br`.

### O2. Short-Term (Next 2 Weeks)

4. **Close the flywheel loop.** Wire `score-templates.sh` output into `select-template.sh` into `dispatch.sh`. This is 90% done -- the scripts exist, they just need to be connected.

5. **Run the prompt optimizer.** Execute `skills/prompt-optimizer/optimize-prompts.sh` on the accumulated run data. Use the recommendations to improve templates.

6. **Consolidate doc-gardener.** Choose one canonical version (recommend the skills version at `skills/doc-gardener/doc-gardener.sh`) and deprecate the other.

7. **Fix `docs/flywheel.md` "Future" labels.** score-templates and select-template are implemented. Update the doc.

### O3. Medium-Term (Next Month)

8. **Implement Relay v1.** The PRD and execution spec are complete and well-reviewed. Focus on Sprint 1 (core: register, send, read, status, gc) and Sprint 2 (reservations, wake). Skip Sprint 4 (daemon) as recommended in the design review.

9. **Implement Learning Loop.** Start with the simplest version: per-run feedback collection and weekly template scoring. The 4-loop architecture from the execution spec is the target, but start with loop 1 only.

10. **Add CI/CD.** The repo has no CI pipeline. At minimum:
    - `tests/run.sh --all` on every push
    - `scripts/prd-lint.sh` on PRD changes
    - `scripts/doc-gardener.sh` on doc changes

### O4. Long-Term (Next Quarter)

11. **Athena Web integration.** The dashboard at port 9000 should show:
    - Live agent status (from `poll-agents.sh --json`)
    - Template performance (from `state/template-scores.json`)
    - Flywheel metrics (from `analyze-runs.sh`)
    - Problem log (from `state/problems.jsonl`)

12. **Multi-repo orchestration.** The orchestrator currently works within the Athena workspace. Extend it to manage beads across all repos under `$HOME`.

13. **Agent capability profiles.** Currently all agents get the same capabilities. Define per-agent profiles: "this agent can modify source code", "this agent can only read and report", "this agent can run tests but not modify code."

---

## Summary of All Findings

### By Severity

**Critical (will cause runtime failures):**
1. `orchestrator/common.sh` uses `br` -- orchestrator cannot find beads (section A1)
2. `test_centurion_us001.py` and `test_centurion_us009.py` test deprecated worktree model -- will fail (section A2, D2)
3. 4 E2E tests use `br` -- will fail if `br` not installed (section D1)

**Major (incorrect behavior or misleading):**
4. `problem-detected.sh` uses `br` -- problem beads not created (section A1)
5. `refine.sh` uses `br` -- refinement workflow broken (section A1)
6. `docs/flywheel.md` labels implemented features as "Future" (section A3)
7. `setup.sh` checks for `br` instead of `bd` (section M1)
8. `bd-to-br-migration` skill has inverted description (section A1)
9. Two different doc-gardener scripts exist (section E4)

**Minor (cosmetic or low-impact):**
10. `code-review/README.md` uses `br update` (section E2)
11. `doc-gardener/examples/athena-integration.sh` uses `br` (section E2)
12. `tdd-dispatch-design.md` references `br` and MCP Agent Mail (section A3)
13. `centurion/PRD.md` scope_paths includes deprecated `worktree-manager.sh` (section A2)
14. `planning-guide.md` mentions "git worktrees" (section A2)
15. `SWARM-playbook-legacy.md` uses `br` (section A1, archive -- expected)
16. `state/SCHEMA.md` references non-existent "SWARM.md" (section A3)
17. `gpt-overnight-run.sh` has hardcoded `/home/perttu` fallback (section B6)

### By Category

| Category | Critical | Major | Minor | Total |
|----------|----------|-------|-------|-------|
| `br` → `bd` migration | 2 | 3 | 4 | 9 |
| Stale worktree references | 1 | 0 | 3 | 4 |
| Stale document content | 0 | 1 | 2 | 3 |
| Duplicate/deprecated code | 0 | 1 | 0 | 1 |
| **Total** | **3** | **5** | **9** | **17** |

### Files Touched by This Analysis

Total files read: 120+

Scripts: 44 files
Templates: 8 files
Tests: 20 files (9 E2E + 13 unit + runner + helpers + 3 fixtures + README)
Skills: 20+ files across 13 skill directories
Docs: 25+ files (guides, features, specs, standards, research, archive)
Config: 5 files (agents.json.example, .gitignore, CLAUDE.md, TOOLS.md.example, MEMORY.md.example)
State: 6 files (schemas, SCHEMA.md, designs, problems.jsonl)
Forge-site: 4 files (HTML, CSS, JS, IMAGE-PROMPTS)
Root: 8 files (README, IDENTITY, mythology, setup.sh, CHANGELOG, SOUL, AGENTS, bad.go)

---

*Analysis complete. No files were modified. All findings include exact file paths and line numbers for remediation.*
