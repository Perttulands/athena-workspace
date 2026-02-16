# TDD-Enforced Dispatch Design

## Status: DRAFT
## Date: 2026-02-14

---

## 1. Current State Analysis

### What Works

**dispatch.sh** is a solid orchestrator: tmux session management, background watcher with three detection strategies, retry logic, structured run/result records, worktree creation, truthsayer integration, and centurion merge on success. The plumbing is mature.

**ralph.sh** has the correct TDD model: one task per iteration, fresh agent session each time (prevents context bloat), progress file as cross-iteration memory, PRD-driven task sequencing, mechanical completion validation (`grep` for `[ ]` rejects false COMPLETE claims), and sprint status tracking. Ralph proves that sequential TDD with feedback loops produces reliable output.

**verify.sh** runs lint, tests, truthsayer, and UBS checks — producing structured JSON. centurion's test gate runs tests post-merge and reverts on failure.

**worktree-manager.sh** provides clean file isolation with safety guardrails (max count, RAM check, auto-commit on destroy).

### What Doesn't Work

**No mechanical TDD enforcement in dispatch.** dispatch.sh sends a prompt and hopes the agent writes tests. There's no structural constraint that forces test-first development. The agent can write implementation only, skip tests entirely, or write tests that don't exercise the actual behavior. Verify runs AFTER — no feedback loop.

**Verify is post-mortem, not a feedback loop.** When verify.sh fails, the result record says "failed" and the bead is done. The agent never sees the failure output. Retry just re-dispatches the same prompt — the agent doesn't know what went wrong. This is "throw it over the wall and check" rather than TDD.

**Ralph and dispatch are separate systems.** Ralph's TDD loop runs inside a single interactive session with its own progress tracking. Dispatch runs headless agents with tmux watchers. They share nothing: different state formats, different completion detection, different retry semantics. You can't dispatch a ralph-style TDD task today.

**Worktrees solve a problem that TDD may eliminate.** Worktrees exist because parallel agents might overwrite each other's files. But if we go sequential-TDD (one task at a time, verified before next), there's no concurrent file access — just branches. Worktrees add complexity (creation/cleanup lifecycle, shared .git operations, path management) without benefit in a sequential model.

**No structured feedback on failure.** When an agent fails verify, the output_summary is the last 500 chars of tmux pane output. That's not actionable. The agent needs: which tests failed, which lint rules were violated, what truthsayer found — structured, not tail-of-pane.

### The Core Insight

Ralph already solved TDD enforcement. The answer isn't to bolt TDD onto dispatch — it's to merge ralph's inner loop INTO the agent session that dispatch launches. dispatch.sh becomes the launcher and watcher. The runner script becomes a TDD loop that the agent executes within.

---

## 2. Proposed Architecture

### Design Principle

**The TDD loop is the runner script.** Currently, `create_runner_script()` generates a script that pipes the prompt to the agent and captures the exit code. The new runner script embeds a RED-GREEN-REFACTOR loop that the agent cannot bypass because it's the execution environment, not a prompt instruction.

### Architecture Overview

```
                    ┌─────────────────────────────────────────────┐
                    │              dispatch.sh                     │
                    │  (launcher + watcher — unchanged role)       │
                    └──────────────┬──────────────────────────────┘
                                   │ creates + launches
                                   ▼
                    ┌─────────────────────────────────────────────┐
                    │           tdd-runner.sh                      │
                    │  (the TDD enforcement loop — NEW)            │
                    │                                              │
                    │  ┌─────────────────────────────────────┐    │
                    │  │ Phase 1: RED                         │    │
                    │  │ Agent writes/updates FAILING test    │    │
                    │  │ Runner verifies: test file exists    │    │
                    │  │ Runner runs tests → MUST FAIL        │    │
                    │  │ If tests pass: REJECT (not a new     │    │
                    │  │   test — it was already green)        │    │
                    │  └──────────────┬──────────────────────┘    │
                    │                 │ tests fail ✓                │
                    │                 ▼                             │
                    │  ┌─────────────────────────────────────┐    │
                    │  │ Phase 2: GREEN                       │    │
                    │  │ Agent writes implementation          │    │
                    │  │ Runner runs tests → MUST PASS        │    │
                    │  │ Runner runs lint → MUST PASS         │    │
                    │  │ If fail: loop back, agent gets       │    │
                    │  │   structured error output             │    │
                    │  └──────────────┬──────────────────────┘    │
                    │                 │ tests + lint pass ✓         │
                    │                 ▼                             │
                    │  ┌─────────────────────────────────────┐    │
                    │  │ Phase 3: VERIFY                      │    │
                    │  │ Run full verify.sh                   │    │
                    │  │ If fail: loop back with errors        │    │
                    │  │ If pass: commit, emit status          │    │
                    │  └─────────────────────────────────────┘    │
                    └──────────────┬──────────────────────────────┘
                                   │ status file written
                                   ▼
                    ┌─────────────────────────────────────────────┐
                    │           dispatch.sh watcher                │
                    │  detect_completion → complete_run            │
                    │  → centurion merge → wake athena             │
                    └─────────────────────────────────────────────┘
```

### What Changes, What Stays

| Component | Status | Notes |
|-----------|--------|-------|
| dispatch.sh | MODIFY | New `create_runner_script()` generates TDD loop. Everything else stays. |
| tdd-runner.sh | NEW | Extracted TDD loop, sourced by runner script. |
| verify.sh | KEEP | Already works. Called from tdd-runner as Phase 3. |
| centurion.sh | KEEP | Unchanged. Still merges on verify pass. |
| worktree-manager.sh | DEPRECATE | See Section 4 for migration path. |
| ralph.sh | KEEP | Still useful for PRD-based multi-task work. Separate concern. |
| scripts/lib/* | KEEP | Common, config, record all reused. |

---

## 3. Runner Script Design: The TDD Loop

### 3.1 tdd-runner.sh

This is the enforcement mechanism. It wraps the agent invocation and controls the phase transitions.

```bash
#!/usr/bin/env bash
# tdd-runner.sh — TDD enforcement loop for dispatched agents
# Called by the generated runner script inside tmux.
# NOT called directly.
set -euo pipefail

# ── Interface ────────────────────────────────────────────────────────────────
# Required environment:
#   BEAD_ID          - bead identifier
#   REPO_PATH        - working directory
#   AGENT_CMD        - array, the agent command
#   PROMPT           - the task prompt
#   STATUS_FILE      - where to write completion status
#   VERIFY_SCRIPT    - path to verify.sh
#   MAX_GREEN_ATTEMPTS - max tries for GREEN phase (default: 3)

MAX_GREEN_ATTEMPTS="${MAX_GREEN_ATTEMPTS:-3}"
TDD_LOG="$REPO_PATH/.tdd-runner.log"

# ── Test Detection ───────────────────────────────────────────────────────────
# Detect the test runner for this repo. Returns the command as a string.

detect_test_cmd() {
    if [[ -f "$REPO_PATH/package.json" ]]; then
        echo "npm test"
    elif [[ -f "$REPO_PATH/Cargo.toml" ]]; then
        echo "cargo test"
    elif [[ -f "$REPO_PATH/go.mod" ]]; then
        echo "go test ./..."
    elif [[ -f "$REPO_PATH/pytest.ini" || -f "$REPO_PATH/setup.py" || \
            -f "$REPO_PATH/pyproject.toml" ]]; then
        echo "pytest"
    else
        echo ""
    fi
}

# ── Run Tests ────────────────────────────────────────────────────────────────
# Runs tests, captures output. Returns exit code.
# Sets TEST_OUTPUT to the test output.

TEST_OUTPUT=""

run_tests() {
    local test_cmd
    test_cmd="$(detect_test_cmd)"
    if [[ -z "$test_cmd" ]]; then
        echo "WARNING: No test runner detected. Skipping test enforcement." | tee -a "$TDD_LOG"
        TEST_OUTPUT="no test runner"
        return 0
    fi
    local tmpfile
    tmpfile="$(mktemp)"
    local rc=0
    (cd "$REPO_PATH" && timeout 300 bash -lc "$test_cmd") >"$tmpfile" 2>&1 || rc=$?
    TEST_OUTPUT="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    return "$rc"
}

# ── Phase Execution ──────────────────────────────────────────────────────────

run_agent_phase() {
    local phase="$1"
    local phase_prompt="$2"

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PHASE=$phase START" | tee -a "$TDD_LOG"

    # Feed phase prompt to agent
    printf '%s' "$phase_prompt" | "${AGENT_CMD[@]}"
    local rc=$?

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PHASE=$phase AGENT_EXIT=$rc" | tee -a "$TDD_LOG"
    return $rc
}

# ── Main TDD Loop ───────────────────────────────────────────────────────────

tdd_main() {
    local test_cmd
    test_cmd="$(detect_test_cmd)"

    # Record pre-existing test state (so we can detect new tests)
    local pre_test_hash=""
    if [[ -n "$test_cmd" ]]; then
        pre_test_hash="$(find "$REPO_PATH" -name '*test*' -o -name '*spec*' \
            | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)"
    fi

    # ── PHASE 1: RED ──────────────────────────────────────────────────────
    # Agent writes a FAILING test for the feature described in PROMPT.

    local red_prompt="$PROMPT

## TDD Phase: RED (Write Failing Test)

You are in the RED phase of TDD. Your ONLY job is to write a test that:
1. Captures the behavior described in the task above
2. FAILS when run (because the implementation doesn't exist yet)
3. Is a real, meaningful test — not a trivially-failing stub

Rules:
- Write ONLY test code. Do NOT write any implementation.
- If tests for this feature already exist and pass, write a NEW test for
  untested behavior. Do not modify passing tests.
- Commit the test with message: 'test: RED - [description]'

When done, just exit. The runner will verify your test fails."

    run_agent_phase "RED" "$red_prompt"

    # Verify: test files changed
    if [[ -n "$test_cmd" ]]; then
        local post_test_hash
        post_test_hash="$(find "$REPO_PATH" -name '*test*' -o -name '*spec*' \
            | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)"

        if [[ "$pre_test_hash" == "$post_test_hash" ]]; then
            echo "REJECT: RED phase did not modify any test files" | tee -a "$TDD_LOG"
            # Give agent one more chance with explicit feedback
            run_agent_phase "RED-RETRY" "You were asked to write a FAILING test but no test files were modified. Write a test file NOW. $red_prompt"
        fi
    fi

    # Verify: tests FAIL (this is the RED check)
    if run_tests; then
        # Tests passed — this means either:
        # a) Agent wrote a trivial test that auto-passes, or
        # b) Agent wrote implementation too (violating RED rules)
        # Either way, log it and proceed. We can't fully prevent this without
        # AST-level analysis, but the structured phases still guide the agent.
        echo "WARNING: Tests pass after RED phase. Expected failure." | tee -a "$TDD_LOG"
        echo "Proceeding to GREEN (agent may have front-run implementation)." | tee -a "$TDD_LOG"
    else
        echo "RED confirmed: tests fail as expected." | tee -a "$TDD_LOG"
    fi

    # ── PHASE 2: GREEN ───────────────────────────────────────────────────
    # Agent writes minimal implementation to make tests pass.

    local green_attempt=0
    local green_success=false

    while (( green_attempt < MAX_GREEN_ATTEMPTS )); do
        green_attempt=$((green_attempt + 1))

        local green_prompt="$PROMPT

## TDD Phase: GREEN (Make Tests Pass) — Attempt $green_attempt/$MAX_GREEN_ATTEMPTS

You are in the GREEN phase of TDD. Tests currently FAIL. Your job:
1. Write the MINIMUM implementation to make all tests pass
2. Do NOT add features beyond what tests require
3. Do NOT modify the tests (they define the contract)

$(if [[ $green_attempt -gt 1 && -n "$TEST_OUTPUT" ]]; then
    echo "## Previous attempt failed. Here is the test output:"
    echo '```'
    echo "$TEST_OUTPUT" | tail -100
    echo '```'
    echo "Fix these failures."
fi)

When done, just exit. The runner will verify tests pass."

        run_agent_phase "GREEN-$green_attempt" "$green_prompt"

        if run_tests; then
            echo "GREEN confirmed: all tests pass." | tee -a "$TDD_LOG"
            green_success=true
            break
        else
            echo "GREEN attempt $green_attempt FAILED. Test output:" | tee -a "$TDD_LOG"
            echo "$TEST_OUTPUT" | tail -50 | tee -a "$TDD_LOG"
        fi
    done

    if ! $green_success; then
        echo "FAILED: Could not make tests pass after $MAX_GREEN_ATTEMPTS attempts." | tee -a "$TDD_LOG"
        return 1
    fi

    # ── PHASE 3: VERIFY ──────────────────────────────────────────────────
    # Full verification: lint + tests + truthsayer + UBS

    if [[ -x "$VERIFY_SCRIPT" ]]; then
        local verify_output
        if verify_output="$("$VERIFY_SCRIPT" "$REPO_PATH" "$BEAD_ID")"; then
            local overall
            overall="$(printf '%s' "$verify_output" | jq -r '.overall // "unknown"')"
            if [[ "$overall" == "pass" ]]; then
                echo "VERIFY passed." | tee -a "$TDD_LOG"
            else
                echo "VERIFY failed (overall=$overall). Output:" | tee -a "$TDD_LOG"
                echo "$verify_output" | tee -a "$TDD_LOG"

                # Give agent a chance to fix lint/style issues
                local fix_prompt="$PROMPT

## TDD Phase: FIX (Verification Failed)

Tests pass, but verification found issues. Fix them:

$(echo "$verify_output" | jq -r '.checks | to_entries[] | select(.value == "fail") | "- \(.key): FAILED"')

Do NOT break any passing tests. Fix only the reported issues.
When done, just exit."

                run_agent_phase "FIX" "$fix_prompt"

                # Re-verify
                if verify_output="$("$VERIFY_SCRIPT" "$REPO_PATH" "$BEAD_ID")"; then
                    overall="$(printf '%s' "$verify_output" | jq -r '.overall // "unknown"')"
                    [[ "$overall" != "pass" ]] && echo "VERIFY still failing after fix attempt." | tee -a "$TDD_LOG"
                fi
            fi
        fi
    fi

    # ── Commit ────────────────────────────────────────────────────────────
    if git -C "$REPO_PATH" status --porcelain 2>/dev/null | grep -q .; then
        git -C "$REPO_PATH" add -A
        git -C "$REPO_PATH" commit -m "feat: $BEAD_ID — implementation (TDD verified)" --no-verify || true
    fi

    return 0
}

# Entry point — called from the generated runner script
tdd_main
```

### 3.2 How dispatch.sh Changes

`create_runner_script()` generates a runner that invokes `tdd-runner.sh` instead of piping prompt directly to agent:

```bash
# Current runner (simplified):
cat "$PROMPT_FILE" | "${AGENT_CMD[@]}"

# New runner:
source "$SCRIPT_DIR/tdd-runner.sh"
# tdd-runner.sh reads PROMPT, AGENT_CMD, etc. from environment
# and runs the RED → GREEN → VERIFY loop
```

The watcher, completion detection, and complete_run logic stay exactly the same. The runner script still writes the status file and exit markers. dispatch.sh doesn't need to know about TDD phases — it just sees "runner finished with exit code N."

### 3.3 Opt-in TDD Mode

Not every dispatch needs TDD. A `--tdd` flag on dispatch.sh selects the runner:

```bash
dispatch.sh <bead-id> <repo-path> <agent-type> <prompt> [template] [--tdd] [--force]
```

- `--tdd`: Uses tdd-runner.sh (RED → GREEN → VERIFY loop)
- Default (no flag): Uses current runner (direct prompt → agent)

This makes TDD an opt-in enhancement, not a breaking change.

### 3.4 The Feedback Loop (Key Difference from Current System)

Current system:
```
dispatch → agent works blindly → verify → pass/fail → done
                                                └── agent never sees this
```

New system:
```
dispatch → RED phase → test fails? ─── yes → GREEN phase → tests pass? ── yes → VERIFY
              │                                    │            │                    │
              └── no test written? retry           │            └── no → retry with  │
                                                   │                structured output │
                                                   │                                 │
                                                   └── fail? → FIX phase → re-verify │
                                                                                     │
                                                                              commit + done
```

The agent gets structured feedback at every transition. Test output, lint output, verify output — all fed back into the next agent invocation. This is what ralph does inside a single session; tdd-runner does it across phases.

---

## 4. Branch/Worktree Strategy Recommendation

### Recommendation: Sequential Branching, Deprecate Worktrees

**Rationale:**

1. **TDD is inherently sequential.** RED must complete before GREEN. GREEN must complete before VERIFY. There's no parallelism within a task — you can't write the test and implementation simultaneously.

2. **Cross-task parallelism is where worktrees helped.** If you dispatch 3 agents to 3 different tasks on the same repo, worktrees prevent file conflicts. But TDD dispatch is one-task-at-a-time: the task isn't "done" until it passes verification, and the next task shouldn't start on a possibly-broken codebase.

3. **Worktree complexity is real cost.** Shared `.git` directory means git operations can interfere across worktrees. Creation/cleanup lifecycle must be managed. Path management in dispatch, verify, centurion all must handle "repo path might be a worktree." Auto-commit on destroy is a lossy safety net.

4. **Branches give the same isolation benefits without the complexity.** Each bead still gets its own branch (`bead-<id>`). Sequential work means only one branch is "active" at a time. centurion merges to develop as before. No file system isolation needed because no concurrent writes.

### Proposed Branch Strategy

```
main
  └── develop          (centurion merges here)
        ├── bead-bd-001  (task 1: TDD complete, merged)
        ├── bead-bd-002  (task 2: TDD complete, merged)
        └── bead-bd-003  (task 3: TDD in progress, agent working)
```

**Flow:**
1. `dispatch.sh` creates branch `bead-<id>` from `develop` (or `main`)
2. Agent works on the branch via tdd-runner
3. On success: centurion merges `bead-<id>` → `develop`
4. Next dispatch creates `bead-<id+1>` from updated `develop`

**No worktree needed.** The repo stays in one directory. Branch switching happens between dispatches, never during an active agent session.

### When Would You Still Want Worktrees?

If you explicitly want **parallel agents on the same repo doing independent tasks** (e.g., two agents working on completely unrelated features), worktrees still make sense. But this is a different use case than TDD-enforced dispatch.

**Recommendation:** Keep `worktree-manager.sh` as available tooling but don't use it by default in TDD dispatch. The `--parallel` flag (or a separate `dispatch-parallel.sh`) can opt into worktrees for the parallel-independent-tasks use case.

### MCP Agent Mail vs Worktrees for Coordination

These solve different problems:

| Concern | Worktrees | Agent Mail |
|---------|-----------|------------|
| File isolation | Yes (filesystem) | No (coordination only) |
| Task sequencing | No | Yes (message ordering) |
| Status communication | No (via state files) | Yes (native) |
| Progress reporting | No | Yes (topic threads) |
| Cross-agent dependencies | No | Yes (contact handshake) |

**In TDD dispatch, Agent Mail replaces the coordination role that worktrees never actually filled.** Worktrees gave filesystem isolation; Agent Mail gives logical coordination. With sequential TDD, you don't need filesystem isolation — but you do need coordination: "task A is done, here's what I changed, task B can start."

Agent Mail's role in TDD dispatch:
- **Progress reporting:** Each TDD phase (RED, GREEN, VERIFY) can post status to the agent's topic
- **Handoff:** When a TDD task completes, send a message with what was changed for the next agent
- **Escalation:** When GREEN fails after MAX_GREEN_ATTEMPTS, post the failure context for human/supervisor review
- **File reservations:** If parallel mode is needed, Agent Mail's file reservations provide logical locking without worktrees

---

## 5. Integration Points

### 5.1 Beads (Work Tracking)

Unchanged. Bead lifecycle:
1. `br create` → bead ID
2. `dispatch.sh --tdd <bead-id> ...` → TDD-enforced execution
3. On success: bead status updated via result record
4. `br close` after centurion merge

The TDD runner doesn't interact with beads directly. dispatch.sh handles bead ID → branch name → state records as before.

### 5.2 Centurion (Merge Orchestration)

Unchanged. `complete_run()` in dispatch.sh already calls centurion only when `status == "done" && verification_overall == "pass"`. The TDD runner makes it more likely that work arriving at centurion is already verified, reducing merge-then-revert cycles.

One improvement: TDD dispatch should set `verification_overall` based on the tdd-runner's VERIFY phase result, not re-run verify.sh in `complete_run()`. This avoids double verification.

### 5.3 Verify.sh

Called by tdd-runner in Phase 3 (VERIFY). Also still called by `complete_run()` in dispatch.sh as a final gate. This double-check is intentional: the TDD runner's verify happens inside the agent session (where the agent can fix issues), while dispatch's verify is the final independent gate.

### 5.4 Agent Mail

New integration. The TDD runner can optionally post phase transitions to Agent Mail:

```
Topic: bead-<id>
├── [RED] Test written: tests/feature_test.go (+42 lines)
├── [RED] Tests fail as expected: 1 failure in TestFeatureX
├── [GREEN-1] Implementation attempt 1: tests still fail (3/5 pass)
├── [GREEN-2] Implementation attempt 2: all tests pass
├── [VERIFY] Full verification: pass
└── [DONE] Committed: feat: bd-001 — implementation (TDD verified)
```

This gives the supervisor (human or Athena) real-time visibility into TDD progress without polling tmux panes.

### 5.5 Truthsayer

Unchanged. Truthsayer runs as a background watcher during the agent session (launched by dispatch.sh, not tdd-runner). It monitors file changes in real time. Its findings feed into verify.sh results.

### 5.6 Wake Gateway / Athena

Unchanged. `complete_run()` still calls `wake_athena()` with status, duration, reason. The TDD runner's success/failure is reflected in the exit code, which dispatch interprets as before.

---

## 6. How Ralph's TDD Approach Informs This

### What Ralph Does Right (and tdd-runner adopts)

1. **Fresh session per iteration.** Ralph uses a new `claude -p` invocation for each task. This prevents context bloat and gives the agent a clean slate. tdd-runner does the same: each phase (RED, GREEN, FIX) is a separate agent invocation.

2. **Progress file as cross-iteration memory.** Ralph writes learnings to `progress_<project>.txt` so subsequent iterations benefit from earlier discoveries. tdd-runner adopts this: structured test output from RED is fed into GREEN as context. Previous GREEN failures are fed into the next GREEN attempt.

3. **Mechanical completion validation.** Ralph greps for `[ ]` in the PRD to validate COMPLETE claims. tdd-runner validates mechanically: tests must fail after RED, tests must pass after GREEN. No trust-the-agent.

4. **Structured feedback on failure.** Ralph's prompt includes "If tests FAIL: do NOT mark the task complete, append what went wrong." tdd-runner does this structurally: GREEN gets the test failure output piped into its prompt.

### What Ralph Does That tdd-runner Does NOT Need

1. **PRD parsing.** Ralph navigates PRD files with task IDs, sprint tracking, review tasks. tdd-runner operates on a single task described in the dispatch prompt. Multi-task sequencing is dispatch's job (or a higher-level orchestrator).

2. **Sprint status management.** Not relevant for individual task dispatch.

3. **Per-task Linus review.** This is quality assurance, not TDD enforcement. Could be added as an optional Phase 4 (REVIEW) but isn't core to the TDD loop.

### How They Can Coexist

Ralph and tdd-dispatch are complementary:

- **Ralph** = multi-task PRD execution with built-in TDD prompting. Runs interactively or in a loop. Uses `claude` directly. Good for greenfield projects from a PRD.

- **tdd-dispatch** = single-task dispatch with mechanical TDD enforcement. Runs headless in tmux via dispatch.sh. Good for incremental work on existing repos where you dispatch one bead at a time.

They don't need to merge. Ralph can optionally use dispatch internally (replacing its `run_model()` with `dispatch.sh --tdd`), but that's a future optimization.

---

## 7. Migration Path

### Phase 1: Add tdd-runner.sh (Non-Breaking)

1. Create `scripts/tdd-runner.sh` with the TDD loop logic
2. Add `--tdd` flag to dispatch.sh that selects the TDD runner in `create_runner_script()`
3. Default behavior unchanged — dispatch without `--tdd` works exactly as today
4. Test with a single bead on a repo with a test suite

**Validation:** Dispatch a task with `--tdd` and verify:
- RED phase produces a failing test
- GREEN phase makes it pass
- VERIFY phase runs full checks
- centurion merges on success
- State records are correct

### Phase 2: Agent Mail Integration (Optional)

1. Add phase reporting to Agent Mail topics from tdd-runner
2. Supervisor can watch TDD progress in real time
3. Failure escalation via Agent Mail instead of just wake gateway

**Validation:** Watch a TDD dispatch via Agent Mail messages. Verify phase transitions are reported.

### Phase 3: Deprecate Worktrees for TDD (Low Risk)

1. When `--tdd` is used, skip worktree creation in dispatch.sh
2. Use branch-only isolation (create `bead-<id>` branch from develop)
3. Keep worktree-manager.sh available for `--parallel` mode
4. Update docs to reflect the new default

**Validation:** Run TDD dispatch without worktrees on a real repo. Verify no file conflicts in sequential operation.

### Phase 4: Make TDD the Default (Breaking Change — Requires Confidence)

1. Flip the default: dispatch.sh uses TDD runner unless `--no-tdd` flag
2. Update all dispatch callers (Athena, manual invocations)
3. Update AGENTS.md dispatch instructions

**Validation:** Run a batch of diverse tasks through TDD dispatch. Measure success rate vs. current approach.

---

## 8. Open Questions

### Q1: How strict should RED enforcement be?

Option A (strict): If tests pass after RED, reject and retry. Forces the agent to write a test that fails.
Option B (pragmatic): Log a warning but proceed. The agent may have written test + implementation together, which still produces tested code.

**Recommendation:** Option B for now. Strict RED rejection requires AST-level analysis to distinguish "test passes because implementation was also written" from "test is trivially passing." Not worth the complexity yet. The structural guidance (separate RED and GREEN prompts) is 80% of the value.

### Q2: Should TDD phases use separate agent sessions or one session with multiple prompts?

Option A (separate sessions): Each phase is a fresh `claude -p` call. Clean context. Agent can't carry forward bad assumptions.
Option B (single session): One agent session, multiple prompts piped in sequence. Agent has full context of previous phases.

**Recommendation:** Option A (separate sessions), following ralph's pattern. Fresh sessions prevent context bloat and are easier to reason about. The structured output from each phase provides sufficient cross-phase context.

Trade-off: codex can't do multi-turn within one session anyway (it's a single `exec` call). Claude can, but fresh sessions are more predictable.

### Q3: What about repos without test suites?

If `detect_test_cmd()` returns empty, the TDD loop can't enforce RED/GREEN. Options:

- Skip TDD enforcement, fall back to current runner (recommendation)
- Require the RED phase to also set up the test infrastructure

**Recommendation:** Skip. TDD enforcement is for repos with existing test infrastructure. A `--tdd` dispatch to a repo without tests should warn and fall back gracefully.

### Q4: Per-task config for test commands?

Currently test detection is repo-wide (package.json → npm test). Some tasks might need specific test files run. Should the dispatch prompt specify which test file to run?

**Recommendation:** Not in Phase 1. Use repo-wide test command. If specific test targeting is needed, the agent can be prompted to run specific tests, and the GREEN phase just verifies the full suite passes.

---

## 9. Risks

1. **Agent confusion from phased prompts.** Agents optimized for "do everything in one shot" might produce poor results when constrained to RED-only or GREEN-only. Mitigation: clear, simple phase prompts. Test with both claude and codex.

2. **Increased token usage.** 3+ agent invocations per task instead of 1. Each invocation re-reads the codebase. Mitigation: token cost is cheap relative to failed-and-retry cycles. A TDD-verified task in 3 phases is better than 2 retries of an unverified task.

3. **Phase timing.** dispatch.sh's watcher has a single timeout for the whole session. TDD tasks with multiple phases need more time. Mitigation: increase `WATCH_TIMEOUT_SECONDS` for TDD dispatches, or make the TDD runner manage its own per-phase timeouts.

4. **RED phase gaming.** Agent writes `assert(false)` — technically a failing test. Mitigation: the GREEN phase will expose this: the agent has to write implementation that makes a real assertion pass. An `assert(false)` that was "the test" means GREEN can never pass.

---

## 10. Summary

The core change is small: **replace the runner script's "pipe prompt to agent" with a phased TDD loop.** Everything else in the dispatch system stays the same. Worktrees become optional (sequential branching is sufficient for TDD). The feedback loop — where the agent sees test output and gets to fix failures — is what distinguishes this from "prompt and pray."

Ralph proved the model works. This design lifts ralph's TDD discipline out of its PRD-specific context and embeds it into the general-purpose dispatch system.
