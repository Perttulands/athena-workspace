# Centurion Implementation Roadmap

_Generated: 2026-02-19_
_Source: PRD at `docs/features/centurion/PRD.md` + implementation at `scripts/centurion.sh`_

---

## 1. Current State Summary

### What Exists

| Component | Status | Location |
|-----------|--------|----------|
| **Main script** | ✅ Working | `scripts/centurion.sh` (~150 LOC) |
| **Test gate** | ✅ Working | `scripts/lib/centurion-test-gate.sh` |
| **Wake notifications** | ✅ Working | `scripts/lib/centurion-wake.sh` |
| **Lock mechanism** | ✅ Working | PID-based lock file in `/tmp/` |
| **Result output** | ✅ Working | JSON to `state/results/<branch>-centurion.json` |

### Current Capabilities

1. **`merge <branch> <repo>`** — Test-gated merge to main
   - Validates git repo and branch existence
   - Refuses dirty worktree
   - Lock file prevents concurrent merges per repo
   - Performs `--no-ff` merge
   - Auto-detects test runner (npm/go/cargo or config override)
   - Reverts merge on test failure
   - Writes JSON result file
   - Notifies wake-gateway on success/failure

2. **`status [repo]`** — Shows branch status for configured repos

### What's Missing

- **No Truthsayer integration** — PRD claims it runs, but no code path exists
- **No lint checks** — PRD mentions lint, not implemented
- **No semantic review** — Pure mechanical gate
- **No conflict resolution** — Aborts on conflict with no recovery
- **No quality levels** — Single mode only
- **No Senate escalation** — No external integration points

---

## 2. Target State Summary

From PRD Definition of Done:

| # | Requirement | Current |
|---|-------------|---------|
| 1 | Basic gate works (tests, truthsayer) | ⚠️ Tests only |
| 2 | Lock file prevents races | ✅ Done |
| 3 | Semantic code review (agent-based) | ❌ Missing |
| 4 | Test gaming detection | ❌ Missing |
| 5 | Merge conflict resolution | ❌ Missing |
| 6 | Senate escalation for ambiguous cases | ❌ Missing |
| 7 | Quality level selection | ❌ Missing |

### Target Architecture

```
┌─────────────────────────────────────────────────────┐
│                   centurion.sh                       │
│  ┌─────────────────────────────────────────────┐    │
│  │ Quality Levels                               │    │
│  │  quick → lint + fast tests                   │    │
│  │  standard → full tests + truthsayer + lint   │    │
│  │  deep → standard + semantic review           │    │
│  └─────────────────────────────────────────────┘    │
│                        │                             │
│  ┌──────────┬──────────┼──────────┬────────────┐    │
│  │          │          │          │            │    │
│  ▼          ▼          ▼          ▼            ▼    │
│ Tests   Truthsayer   Lint    Semantic     Conflict  │
│                               Review      Resolver  │
│                                 │            │      │
│                                 └────┬───────┘      │
│                                      ▼              │
│                                   Senate            │
│                                 (escalation)        │
└─────────────────────────────────────────────────────┘
```

---

## 3. Gap Analysis

### Gap 1: Truthsayer Integration (Claimed but Missing)

**PRD says:** "Runs Truthsayer — No error-severity findings"
**Reality:** No Truthsayer invocation exists in the codebase

**Impact:** Medium — Consistency risk between docs and implementation
**Effort:** Small — Call existing truthsayer tool/script

### Gap 2: Lint Integration (Mentioned but Missing)

**PRD says:** "Runs linters — Code style checks"
**Reality:** No lint runner in test-gate or main script

**Impact:** Low — Many repos have lint in test suite
**Effort:** Small — Add configurable lint command

### Gap 3: Quality Levels (Not Implemented)

**PRD defines:**
| Level | Checks | When |
|-------|--------|------|
| Quick | Lint + fast tests | Pre-commit |
| Standard | Full tests + Truthsayer | PR merge |
| Deep | Standard + semantic review | Main merge |

**Reality:** Single mode runs all tests

**Impact:** Medium — Can't tune gate strictness
**Effort:** Medium — Restructure gate logic, add CLI flag

### Gap 4: Semantic Code Review (Major Feature Gap)

**PRD says:** "Review the diff for correctness... Centurion should be an intelligent agent"
**Reality:** Pure bash script, no AI integration

**Impact:** High — Core differentiator missing
**Effort:** Large — Requires agent integration, prompt engineering, decision logic

### Gap 5: Test Gaming Detection (Not Implemented)

**PRD says:** "Check if tests actually test the code (not gaming)"
**Reality:** No diff analysis for test modifications

**Impact:** High — Agents can currently game the gate
**Effort:** Medium — Diff analysis + heuristics or AI review

### Gap 6: Merge Conflict Resolution (Fails Fast)

**PRD says:** "Centurion attempts automatic resolution... If ambiguous, escalates to Senate"
**Reality:** `git merge --abort` on any conflict

**Impact:** Medium — Manual intervention required for conflicts
**Effort:** Medium-Large — Conflict detection, auto-resolution, Senate protocol

### Gap 7: Senate Escalation (No Integration Point)

**PRD says:** "Escalates ambiguous cases to Senate"
**Reality:** No Senate interface exists

**Impact:** Medium — Blocks conflict resolution and semantic review escalation
**Effort:** Medium — Define protocol, implement messaging

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Complete the Basics)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **CEN-001** | Add Truthsayer Integration | Add `run_truthsayer()` to test-gate library. Call Truthsayer on the repo, fail gate on error-severity findings. Respect config timeout. | None | S | Truthsayer runs on every merge. Error findings block merge. JSON result includes truthsayer output. |
| **CEN-002** | Add Lint Integration | Add `run_lint()` to test-gate library. Auto-detect linter (eslint/golangci-lint/cargo clippy) or use config `lint_cmd`. | None | S | Lint runs on merge. Failures block merge. Configurable per-repo. |
| **CEN-003** | Implement Quality Levels | Add `--level quick|standard|deep` flag. Quick: lint only. Standard: lint+tests+truthsayer. Deep: standard (semantic review placeholder). | CEN-001, CEN-002 | M | `centurion.sh merge --level quick` works. Default is `standard`. |

### Phase 2: Intelligence (Agent-Based Review)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **CEN-004** | Semantic Review Scaffolding | Create `scripts/lib/centurion-semantic.sh`. Extract diff, format prompt, shell out to Claude CLI. Return pass/fail/review-needed. | None | M | `run_semantic_review()` function exists. Returns structured result. |
| **CEN-005** | Semantic Review Prompt Engineering | Write review prompt in `skills/centurion-review.md`. Focus on: correctness, test coverage, suspicious patterns, naming. | CEN-004 | M | Prompt file exists. Reviews catch obvious issues in test cases. |
| **CEN-006** | Test Gaming Detection | In semantic review, specifically check: tests removed, assertions weakened, test coverage for changed code. Flag if suspicious. | CEN-004, CEN-005 | M | Gaming attempts (test removal, assertion changes) are flagged. False positive rate < 20%. |
| **CEN-007** | Integrate Semantic Review into Deep Mode | Wire `run_semantic_review()` into `--level deep`. Fail gate or escalate based on review result. | CEN-003, CEN-004, CEN-005 | S | `centurion.sh merge --level deep` runs semantic review. |

### Phase 3: Conflict Handling

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **CEN-008** | Conflict Detection & Reporting | On conflict, extract conflicting files and hunks. Write detailed conflict report to result JSON. | None | S | Conflict result includes file list and conflict markers. |
| **CEN-009** | Auto-Resolve Trivial Conflicts | For non-overlapping changes (theirs/ours clear), auto-resolve. Use `git checkout --ours/--theirs` for disjoint file changes. | CEN-008 | M | Simple conflicts (different files, append-only) auto-resolve. Complex conflicts still abort. |
| **CEN-010** | Senate Escalation Protocol | Define Senate request format (JSON). Write `escalate_to_senate()` helper. Queue request to `state/senate-inbox/`. | None | M | Escalation writes valid request. Senate (when built) can process it. |
| **CEN-011** | Conflict Resolution via Senate | For ambiguous conflicts: extract options, escalate to Senate, await verdict, apply resolution. | CEN-009, CEN-010 | L | Ambiguous conflicts trigger Senate request. Resolution applied on verdict. |

### Phase 4: Operational Excellence

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **CEN-012** | Structured Logging | Replace echo with leveled logging (debug/info/warn/error). Add `--verbose` and `--quiet` flags. | None | S | Logs are structured. `--quiet` shows only pass/fail. `--verbose` shows all steps. |
| **CEN-013** | Metrics & History | Write merge metrics (duration, checks run, result) to append-only log. Add `centurion.sh history` command. | None | M | `state/centurion-history.jsonl` tracks all runs. `history` command shows recent. |
| **CEN-014** | Dry-Run Mode | Add `--dry-run` flag. Run all checks but don't commit merge. | None | S | `--dry-run` validates without merging. Exit code reflects would-pass/would-fail. |
| **CEN-015** | Pre-commit Hook Integration | Add `centurion.sh check` command for quick pre-commit validation. Document hook setup. | CEN-003 | S | `centurion.sh check .` runs quick checks. Hook example in docs. |

---

## 5. Recommended First Three Tasks

### 1. CEN-001: Add Truthsayer Integration

**Why first:** PRD claims this works but it doesn't. Fixing documentation/implementation mismatch is foundational.

**Dispatch prompt:**
```
Add Truthsayer integration to Centurion test gate.

Files to modify:
- scripts/lib/centurion-test-gate.sh

Requirements:
1. Add run_truthsayer() function
2. Call truthsayer scan on repo_path
3. Parse output for error-severity findings
4. Return failure if errors found
5. Call run_truthsayer() from centurion.sh after tests pass
6. Include truthsayer output in result JSON on failure

Test: Create a file with a truthsayer error pattern, verify merge is blocked.
```

---

### 2. CEN-002: Add Lint Integration

**Why second:** Completes "mechanical checks" foundation before adding intelligence.

**Dispatch prompt:**
```
Add lint integration to Centurion test gate.

Files to modify:
- scripts/lib/centurion-test-gate.sh

Requirements:
1. Add run_lint() function
2. Auto-detect linter:
   - package.json with eslint → npx eslint .
   - go.mod → golangci-lint run (if available) or go vet
   - Cargo.toml → cargo clippy
3. Support config override via repos[repo].lint_cmd in config
4. Run lint before tests (fast fail)
5. Include lint output in result JSON on failure

Test: Create a lint error in test repo, verify merge is blocked.
```

---

### 3. CEN-003: Implement Quality Levels

**Why third:** Enables fast iteration (quick mode) and sets up structure for deep mode.

**Dispatch prompt:**
```
Implement quality levels in Centurion.

Files to modify:
- scripts/centurion.sh
- scripts/lib/centurion-test-gate.sh

Requirements:
1. Add --level flag to merge command (values: quick, standard, deep)
2. Default to standard
3. Quick mode: lint only (skip tests, skip truthsayer)
4. Standard mode: lint + tests + truthsayer
5. Deep mode: same as standard (semantic review placeholder, log "deep mode: semantic review not yet implemented")
6. Update usage/help text
7. Include quality level in result JSON

Test:
- centurion.sh merge --level quick <branch> <repo> → runs lint only
- centurion.sh merge --level standard <branch> <repo> → runs all
- centurion.sh merge <branch> <repo> → defaults to standard
```

---

## Appendix: Dependency Graph

```
CEN-001 (Truthsayer) ──┐
                       ├──→ CEN-003 (Quality Levels) ──→ CEN-007 (Wire Semantic)
CEN-002 (Lint) ────────┘                                        ↑
                                                                │
CEN-004 (Semantic Scaffold) ──→ CEN-005 (Prompts) ──→ CEN-006 (Gaming) ─┘

CEN-008 (Conflict Report) ──→ CEN-009 (Auto-Resolve) ──┐
                                                        ├──→ CEN-011 (Senate Resolve)
CEN-010 (Senate Protocol) ─────────────────────────────┘

CEN-012, CEN-013, CEN-014, CEN-015 — Independent, can parallelize
```

---

## Success Metrics

| Metric | Baseline | Target |
|--------|----------|--------|
| Merge gate coverage | Tests only | Tests + Lint + Truthsayer + Semantic |
| Gaming detection | 0% | >80% of obvious gaming caught |
| Conflict auto-resolution | 0% | >50% of simple conflicts |
| Gate latency (standard) | ~30s | <60s |
| Gate latency (quick) | N/A | <10s |
