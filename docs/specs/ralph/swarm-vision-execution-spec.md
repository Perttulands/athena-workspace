---
feature_slug: swarm-vision
primary_bead: bd-11t
status: active
owner: athena
scope_paths:
  - scripts/dispatch.sh
  - scripts/verify.sh
  - scripts/orchestrator.sh
  - docs/
last_updated: 2026-02-18
source_of_truth: false
---
# Execution Spec: Autonomous Agentic Coding Factory

**Project**: swarm_vision
**Progress file**: `progress_swarm_vision.txt`
**Executor**: `./scripts/ralph.sh swarm_vision`

---

## Overview

Transform the current dispatch-and-verify swarm into a self-improving autonomous coding factory. The system will: produce rich structured records of every run, enforce quality mechanically, learn from its own history to improve template selection, and ultimately operate overnight without human supervision — reading state, making real decisions, and adapting when things go sideways.

**Existing system**: `dispatch.sh` spawns agents in tmux, writes run/result JSON to `state/`, `verify.sh` checks repos, `analyze-runs.sh` produces flywheel reports, prompt templates live in `templates/`.

**What this PRD adds**: Rich run context, schema enforcement, structured docs, custom linters, automatic verify integration, architecture enforcement, analysis-driven template selection, doc gardening, prompt scoring, overnight orchestration, goal-to-task planning, calibration learning, and git worktree isolation.

**Tech stack**: Bash/shell scripts, Node.js (for linters/scoring), jq for JSON, JSON Schema for validation. Ubuntu Linux.

---

## Sprint 1: State & Foundation

**Goal**: Rich run records with full context, schema enforcement on all state writes, structured docs directory as system of record.
**Status:** COMPLETE

---

- [x] **US-001**: Enrich run records with output_summary and failure_reason fields (15 min)

**Files:**
- Modify: `state/schemas/run.schema.json`
- Modify: `state/schemas/result.schema.json`
- Modify: `scripts/dispatch.sh`
- Modify: `state/SCHEMA.md`

**Context to read first:**
- `state/schemas/run.schema.json` — current schema
- `state/schemas/result.schema.json` — current schema
- `scripts/dispatch.sh` — lines 141-181 (build_run_payload), lines 194-230 (build_result_payload)
- `state/SCHEMA.md` — documentation of fields

**What to implement:**

Add these fields to `run.schema.json`:
- `output_summary` (string, nullable) — first 500 chars of agent stdout captured from tmux pane on completion
- `failure_reason` (string, nullable) — structured reason when status is "failed" or "timeout"
- `template_name` (string, nullable) — which prompt template was used (e.g., "bug-fix", "feature")
- `prompt_full` (string) — full prompt text (rename existing `prompt` which is truncated to 200 chars)

Add `output_summary` field to `result.schema.json`.

Update `dispatch.sh`:
- In `complete_run()`, capture last 500 chars of tmux pane output into `output_summary`
- Pass `output_summary` through `build_run_payload` and `build_result_payload`
- Accept optional 5th argument `template_name` in dispatch.sh CLI (default: "custom")
- Change `PROMPT_TRUNCATED` to keep full prompt in `prompt_full`, truncated in `prompt`

Update `state/SCHEMA.md` to document new fields.

**TDD phases:**

RED:
```bash
# Create test script
cat > /tmp/test-us001.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail
SCHEMA_DIR="state/schemas"

# Test 1: run schema has output_summary field
jq -e '.properties.output_summary' "$SCHEMA_DIR/run.schema.json" || { echo "FAIL: run schema missing output_summary"; exit 1; }

# Test 2: run schema has failure_reason field
jq -e '.properties.failure_reason' "$SCHEMA_DIR/run.schema.json" || { echo "FAIL: run schema missing failure_reason"; exit 1; }

# Test 3: run schema has template_name field
jq -e '.properties.template_name' "$SCHEMA_DIR/run.schema.json" || { echo "FAIL: run schema missing template_name"; exit 1; }

# Test 4: run schema has prompt_full field
jq -e '.properties.prompt_full' "$SCHEMA_DIR/run.schema.json" || { echo "FAIL: run schema missing prompt_full"; exit 1; }

# Test 5: result schema has output_summary field
jq -e '.properties.output_summary' "$SCHEMA_DIR/result.schema.json" || { echo "FAIL: result schema missing output_summary"; exit 1; }

# Test 6: dispatch.sh accepts 5 args
grep -q 'template_name\|TEMPLATE_NAME' scripts/dispatch.sh || { echo "FAIL: dispatch.sh doesn't handle template_name"; exit 1; }

# Test 7: dispatch.sh captures output_summary
grep -q 'output_summary\|OUTPUT_SUMMARY' scripts/dispatch.sh || { echo "FAIL: dispatch.sh doesn't capture output_summary"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
chmod +x /tmp/test-us001.sh
bash /tmp/test-us001.sh
```

GREEN: Implement the schema changes and dispatch.sh modifications.

VERIFY:
```bash
bash /tmp/test-us001.sh
# Expected: ALL TESTS PASSED

# Validate schemas are valid JSON Schema
jq -e '."$schema"' state/schemas/run.schema.json
jq -e '."$schema"' state/schemas/result.schema.json

# Validate dispatch.sh syntax
bash -n scripts/dispatch.sh
```

**Acceptance criteria:**
- [x] `run.schema.json` has `output_summary`, `failure_reason`, `template_name`, `prompt_full` fields
- [x] `result.schema.json` has `output_summary` field
- [x] `dispatch.sh` captures pane output into `output_summary` on completion
- [x] `dispatch.sh` accepts optional 5th argument for template_name
- [x] `state/SCHEMA.md` documents all new fields
- [x] `bash -n scripts/dispatch.sh` passes

---

- [x] **US-002**: Schema validation script with ajv-cli (15 min) [depends: US-001]

**Files:**
- Create: `scripts/validate-state.sh`
- Create: `package.json` (workspace root, minimal — just ajv-cli dep)
- Modify: `state/SCHEMA.md` — document validation usage

**Context to read first:**
- `state/schemas/run.schema.json` — schema to validate against
- `state/schemas/result.schema.json` — schema to validate against
- `scripts/dispatch.sh` — lines 75-116 (existing jq-based validation functions)
- `state/runs/` — sample run records
- `state/results/` — sample result records

**What to implement:**

Create `scripts/validate-state.sh` that:
- Takes `--runs`, `--results`, or `--all` flag
- Validates each JSON file in the target directory against its schema using `ajv-cli`
- Outputs pass/fail per file with clear error messages
- Returns exit code 0 if all pass, 1 if any fail
- Includes `--fix` flag that migrates legacy records (adds missing fields with null/defaults)
- Has `--help` usage text

Create minimal `package.json` at workspace root:
```json
{
  "private": true,
  "devDependencies": {
    "ajv-cli": "^5.0.0"
  }
}
```

Run `npm install` to create node_modules.

**TDD phases:**

RED:
```bash
cat > /tmp/test-us002.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: validate-state.sh exists and is executable
test -x scripts/validate-state.sh || { echo "FAIL: validate-state.sh not executable"; exit 1; }

# Test 2: --help works
scripts/validate-state.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: package.json exists with ajv-cli
jq -e '.devDependencies["ajv-cli"]' package.json || { echo "FAIL: package.json missing ajv-cli"; exit 1; }

# Test 4: Create a valid run record and validate it
mkdir -p /tmp/test-state/runs
cat > /tmp/test-state/runs/test-valid.json << 'JSON'
{"schema_version":1,"bead":"bd-test","agent":"claude","model":"sonnet","repo":"/tmp","prompt":"test","prompt_hash":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","started_at":"2026-01-01T00:00:00Z","finished_at":null,"duration_seconds":null,"status":"running","attempt":1,"max_retries":2,"session_name":"agent-bd-test","result_file":"state/results/bd-test.json","exit_code":null,"output_summary":null,"failure_reason":null,"template_name":null,"prompt_full":"test"}
JSON
scripts/validate-state.sh --runs /tmp/test-state/runs || { echo "FAIL: valid record rejected"; exit 1; }

# Test 5: Create an invalid record (missing required field) — should fail
cat > /tmp/test-state/runs/test-invalid.json << 'JSON'
{"bead":"bad"}
JSON
! scripts/validate-state.sh --runs /tmp/test-state/runs 2>/dev/null || { echo "FAIL: invalid record accepted"; exit 1; }

rm -rf /tmp/test-state
echo "ALL TESTS PASSED"
TESTEOF
chmod +x /tmp/test-us002.sh
bash /tmp/test-us002.sh
```

GREEN: Implement the script and package.json.

VERIFY:
```bash
bash /tmp/test-us002.sh
# Expected: ALL TESTS PASSED
bash -n scripts/validate-state.sh
```

**Acceptance criteria:**
- [x] `scripts/validate-state.sh` exists, is executable, validates state files against JSON schemas
- [x] `--runs`, `--results`, `--all` flags work
- [x] `--fix` migrates legacy records
- [x] `package.json` exists with ajv-cli dependency
- [x] Invalid records produce clear error messages with field names
- [x] Exit code 0 on all-pass, 1 on any-fail

---

- [x] **US-003**: Structured docs directory with index (15 min)

**Files:**
- Create: `docs/INDEX.md`
- Create: `docs/architecture.md`
- Create: `docs/dispatch-flow.md`
- Create: `docs/templates-guide.md`
- Create: `docs/state-schema.md`
- Create: `docs/flywheel.md`
- Create: `scripts/docs-index.sh`

**Context to read first:**
- `SWARM.md` — overall playbook
- `SWARM-IMPLEMENTATION.md` — architecture layers
- `VISION.md` — principles
- `state/SCHEMA.md` — state documentation
- `templates/README.md` — template documentation

**What to implement:**

Create `docs/` directory as the system of record (per Harness Engineering pattern). Each doc is a standalone reference that agents can discover via INDEX.md.

`docs/INDEX.md` — Table of contents for all docs:
```markdown
# Documentation Index

| Document | Purpose | Key audience |
|----------|---------|-------------|
| architecture.md | System layers, dependency direction, component boundaries | All agents |
| dispatch-flow.md | How dispatch.sh works end-to-end | Athena, debugging |
| templates-guide.md | How to use/create prompt templates | Athena |
| state-schema.md | Run/result record formats, validation | Scripts, analysis |
| flywheel.md | Analysis methodology, improvement loop | Analysis agents |
```

Each doc file should be concise (under 100 lines), describe what IS (not history), and be self-contained.

`docs/architecture.md` — Extract from SWARM-IMPLEMENTATION.md layers + VISION.md principles into a single agent-legible reference.

`docs/dispatch-flow.md` — Document the dispatch lifecycle: arguments → preflight → tmux launch → watcher → completion detection → record writing → wake Athena.

`docs/templates-guide.md` — Move content from `templates/README.md` plus variable reference.

`docs/state-schema.md` — Consolidate from `state/SCHEMA.md` into the docs system.

`docs/flywheel.md` — Document the analysis loop: what data is collected, how `analyze-runs.sh` works, what recommendations mean.

Create `scripts/docs-index.sh` that:
- Scans `docs/` for all `.md` files
- Checks each is listed in `docs/INDEX.md`
- Reports any unlisted docs or dead links
- Exit 0 if consistent, exit 1 if drift detected

**TDD phases:**

RED:
```bash
cat > /tmp/test-us003.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: docs/INDEX.md exists
test -f docs/INDEX.md || { echo "FAIL: docs/INDEX.md missing"; exit 1; }

# Test 2: All doc files exist
for f in architecture.md dispatch-flow.md templates-guide.md state-schema.md flywheel.md; do
    test -f "docs/$f" || { echo "FAIL: docs/$f missing"; exit 1; }
done

# Test 3: INDEX.md references all doc files
for f in architecture.md dispatch-flow.md templates-guide.md state-schema.md flywheel.md; do
    grep -q "$f" docs/INDEX.md || { echo "FAIL: INDEX.md missing reference to $f"; exit 1; }
done

# Test 4: Each doc is under 150 lines
for f in docs/*.md; do
    lines=$(wc -l < "$f")
    if (( lines > 150 )); then
        echo "FAIL: $f is $lines lines (max 150)"
        exit 1
    fi
done

# Test 5: docs-index.sh exists and is executable
test -x scripts/docs-index.sh || { echo "FAIL: docs-index.sh not executable"; exit 1; }

# Test 6: docs-index.sh passes (no drift)
scripts/docs-index.sh || { echo "FAIL: docs-index.sh detected drift"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
chmod +x /tmp/test-us003.sh
bash /tmp/test-us003.sh
```

GREEN: Create all docs and the index script.

VERIFY:
```bash
bash /tmp/test-us003.sh
# Expected: ALL TESTS PASSED
bash -n scripts/docs-index.sh
```

**Acceptance criteria:**
- [x] `docs/INDEX.md` exists as table of contents
- [x] All 5 doc files exist and are under 150 lines each
- [x] Each doc describes what IS, not history
- [x] `scripts/docs-index.sh` detects drift between INDEX.md and actual doc files
- [x] No doc content is duplicated verbatim from SWARM.md or other root files

---

- [x] **US-004**: Wire validate-state.sh into dispatch.sh completion path (10 min) [depends: US-002]

**Files:**
- Modify: `scripts/dispatch.sh`

**Context to read first:**
- `scripts/dispatch.sh` — lines 456-489 (`complete_run` function)
- `scripts/validate-state.sh` — the validator from US-002

**What to implement:**

After `dispatch.sh` writes run and result records in `complete_run()`, call `validate-state.sh` to validate the just-written files. If validation fails, log a warning but don't block completion (validation is advisory in this phase).

Add to `complete_run()` after the `write_run_record` and `write_result_record` calls:
```bash
# Advisory schema validation
if [[ -x "$WORKSPACE_ROOT/scripts/validate-state.sh" ]]; then
    if ! "$WORKSPACE_ROOT/scripts/validate-state.sh" --runs "$RUNS_DIR/$BEAD_ID.json" --results "$RESULTS_DIR/$BEAD_ID.json" 2>/dev/null; then
        echo "Warning: schema validation failed for $BEAD_ID records" >&2
    fi
fi
```

**TDD phases:**

RED:
```bash
cat > /tmp/test-us004.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test: dispatch.sh calls validate-state.sh in complete_run
grep -A30 'complete_run()' scripts/dispatch.sh | grep -q 'validate-state' || { echo "FAIL: dispatch.sh doesn't call validate-state.sh"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us004.sh
```

GREEN: Add the validation call.

VERIFY:
```bash
bash /tmp/test-us004.sh
bash -n scripts/dispatch.sh
```

**Acceptance criteria:**
- [x] `dispatch.sh` calls `validate-state.sh` after writing records
- [x] Validation failure logs a warning but does not block completion
- [x] `bash -n scripts/dispatch.sh` passes

---

- [x] **US-REVIEW-S1**: Sprint 1 Review — State & Foundation (10 min) [depends: US-001, US-002, US-003, US-004]

**Review scope:** US-001 through US-004

**Acceptance criteria:**
- [x] All run/result schemas include new fields and validate correctly
- [x] `validate-state.sh` catches invalid records with clear messages
- [x] `docs/` directory is complete, indexed, and under 150 lines per doc
- [x] `dispatch.sh` produces records that pass schema validation
- [x] No code duplication between scripts
- [x] Consistent error handling patterns across all scripts

---

## Sprint 2: Quality & Enforcement

**Goal**: Custom linters with agent-friendly errors, verify.sh as post-completion hook, mechanical architecture enforcement.
**Status:** COMPLETE

---

- [x] **US-005**: Custom linter framework with agent-friendly error messages (20 min)

**Files:**
- Create: `scripts/lint-agent.sh`
- Create: `scripts/lint-rules/` directory
- Create: `scripts/lint-rules/no-hardcoded-paths.sh`
- Create: `scripts/lint-rules/shellcheck-wrapper.sh`
- Create: `scripts/lint-rules/json-valid.sh`
- Create: `scripts/lint-rules/README.md`

**Context to read first:**
- `scripts/verify.sh` — current verification approach
- `scripts/dispatch.sh` — example of well-structured bash
- `reference/harness-engineering-notes.md` — section 4 on mechanical enforcement
- `VISION.md` — principle 1 (structure over discipline) and principle 7 (enforce architecture mechanically)

**What to implement:**

Create a modular linter framework where each rule is a standalone script in `scripts/lint-rules/`. Each rule script:
- Takes a file path or directory as argument
- Outputs structured JSON on failure: `{"rule": "name", "file": "path", "line": N, "message": "what's wrong", "fix": "how to fix it"}`
- Returns 0 on pass, 1 on fail
- The `fix` field is the key innovation — it tells agents exactly how to resolve the issue

`scripts/lint-agent.sh` is the runner:
- Takes a file or directory path
- Runs all rules in `scripts/lint-rules/` that apply (based on file extension)
- Aggregates results as JSON array
- Returns 0 if all rules pass, 1 if any fail
- Supports `--rule <name>` to run a single rule
- Supports `--json` for machine output (default: human-readable with fix instructions)

Initial rules:
1. `no-hardcoded-paths.sh` — Flags absolute paths like `/home/<user>` in scripts (fix: "Use $HOME or relative paths")
2. `shellcheck-wrapper.sh` — Runs shellcheck if available, reformats errors with fix instructions
3. `json-valid.sh` — Validates JSON files with jq, reports line-level errors

**TDD phases:**

RED:
```bash
cat > /tmp/test-us005.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: lint-agent.sh exists and is executable
test -x scripts/lint-agent.sh || { echo "FAIL: lint-agent.sh not executable"; exit 1; }

# Test 2: lint-rules directory exists with rules
test -d scripts/lint-rules || { echo "FAIL: lint-rules/ missing"; exit 1; }
ls scripts/lint-rules/*.sh | wc -l | grep -q '[3-9]' || { echo "FAIL: fewer than 3 rules"; exit 1; }

# Test 3: --help works
scripts/lint-agent.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 4: Valid script passes
echo '#!/bin/bash' > /tmp/test-lint-ok.sh
echo 'echo "hello"' >> /tmp/test-lint-ok.sh
scripts/lint-agent.sh /tmp/test-lint-ok.sh || { echo "FAIL: valid script should pass"; exit 1; }

# Test 5: Hardcoded path fails and includes fix instruction
echo '#!/bin/bash' > /tmp/test-lint-bad.sh
echo 'DIR="$HOME/projects"' >> /tmp/test-lint-bad.sh
output=$(scripts/lint-agent.sh --json /tmp/test-lint-bad.sh 2>&1 || true)
echo "$output" | jq -e '.[0].fix' || { echo "FAIL: no fix instruction in output"; exit 1; }

# Test 6: Invalid JSON file fails
echo '{bad json' > /tmp/test-lint-bad.json
! scripts/lint-agent.sh /tmp/test-lint-bad.json 2>/dev/null || { echo "FAIL: bad JSON should fail"; exit 1; }

rm -f /tmp/test-lint-ok.sh /tmp/test-lint-bad.sh /tmp/test-lint-bad.json
echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us005.sh
```

GREEN: Implement the linter framework and rules.

VERIFY:
```bash
bash /tmp/test-us005.sh
bash -n scripts/lint-agent.sh
for f in scripts/lint-rules/*.sh; do bash -n "$f"; done
```

**Acceptance criteria:**
- [x] `scripts/lint-agent.sh` runs all rules and aggregates results
- [x] Each rule outputs JSON with a `fix` field containing remediation instructions
- [x] `--json` flag outputs machine-readable results
- [x] 3 initial rules work: no-hardcoded-paths, shellcheck-wrapper, json-valid
- [x] Lint rules are individually runnable
- [x] `scripts/lint-rules/README.md` explains how to add new rules

---

- [x] **US-006**: Integrate verify.sh as post-completion hook in dispatch.sh (15 min) [depends: US-005]

**Files:**
- Modify: `scripts/verify.sh` — rewrite to use lint-agent.sh + structured output
- Modify: `scripts/dispatch.sh` — call verify.sh in complete_run(), write verification to records

**Context to read first:**
- `scripts/verify.sh` — current implementation (basic)
- `scripts/dispatch.sh` — `complete_run()` function (line 456)
- `scripts/lint-agent.sh` — from US-005
- `state/schemas/run.schema.json` — needs `verification` field

**What to implement:**

Rewrite `verify.sh` to:
- Call `lint-agent.sh` on changed files (from `git diff --name-only`)
- Run test suite (existing logic, improved)
- Run ubs scan (existing logic)
- Output structured JSON with all check results
- Include `fix` instructions from lint-agent.sh in output

Add `verification` field to `run.schema.json` and `result.schema.json`:
```json
"verification": {
  "type": ["object", "null"],
  "properties": {
    "lint": { "type": "string", "enum": ["pass", "fail", "skipped"] },
    "tests": { "type": "string", "enum": ["pass", "fail", "skipped"] },
    "ubs": { "type": "string", "enum": ["clean", "issues", "skipped"] },
    "lint_details": { "type": ["array", "null"] },
    "overall": { "type": "string", "enum": ["pass", "fail"] }
  }
}
```

Update `dispatch.sh` `complete_run()`:
- After detecting completion, run `verify.sh <repo-path> <bead-id>`
- Capture verification JSON and include it in both run and result records
- Verification failure does NOT change the run status (advisory) — status remains what the agent produced

**TDD phases:**

RED:
```bash
cat > /tmp/test-us006.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: verify.sh outputs valid JSON
output=$(scripts/verify.sh /tmp 2>/dev/null || true)
echo "$output" | jq -e '.checks' || { echo "FAIL: verify.sh doesn't output structured JSON"; exit 1; }

# Test 2: verify.sh includes lint results
echo "$output" | jq -e '.checks.lint' || { echo "FAIL: verify.sh missing lint check"; exit 1; }

# Test 3: run schema has verification field
jq -e '.properties.verification' state/schemas/run.schema.json || { echo "FAIL: run schema missing verification"; exit 1; }

# Test 4: dispatch.sh calls verify.sh in complete_run
grep -A40 'complete_run()' scripts/dispatch.sh | grep -q 'verify.sh' || { echo "FAIL: dispatch.sh doesn't call verify.sh"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us006.sh
```

GREEN: Implement the changes.

VERIFY:
```bash
bash /tmp/test-us006.sh
bash -n scripts/verify.sh
bash -n scripts/dispatch.sh
```

**Acceptance criteria:**
- [x] `verify.sh` calls `lint-agent.sh` on changed files
- [x] `verify.sh` outputs structured JSON with lint, tests, ubs results
- [x] `dispatch.sh` runs `verify.sh` on agent completion
- [x] Verification results are written into run and result records
- [x] Verification failure is advisory (doesn't change run status)
- [x] Schemas updated with `verification` field

---

- [x] **US-007**: Architecture enforcement linter rules (15 min) [depends: US-005]

**Files:**
- Create: `scripts/lint-rules/dependency-direction.sh`
- Create: `scripts/lint-rules/naming-conventions.sh`
- Create: `scripts/lint-rules/file-size-limit.sh`
- Create: `docs/architecture-rules.md`
- Modify: `docs/INDEX.md` — add architecture-rules.md

**Context to read first:**
- `scripts/lint-rules/README.md` — how to add rules (from US-005)
- `SWARM-IMPLEMENTATION.md` — layer architecture
- `reference/harness-engineering-notes.md` — section 4 on invariants
- `VISION.md` — principles 1 and 7

**What to implement:**

Three architecture enforcement rules:

1. `dependency-direction.sh` — Enforces that lower layers don't import/source higher layers:
   - Layer 0 (tools): no imports from workspace
   - Layer 1 (scripts): can use tools, not templates or state analysis
   - Layer 2 (state): can be read by any layer, written only by scripts
   - Layer 3 (templates): can reference docs, not scripts
   - Checks: `source` statements in bash, `require`/`import` in Node.js
   - Fix: "Move shared logic to a lower layer or use a callback pattern"

2. `naming-conventions.sh` — Enforces naming:
   - Scripts: kebab-case (`*.sh`)
   - State files: `<bead-id>.json` pattern
   - Docs: kebab-case `.md`
   - Templates: kebab-case `.md`
   - Fix: "Rename file to match convention: <suggested-name>"

3. `file-size-limit.sh` — Flags files over 300 lines (scripts) or 150 lines (docs):
   - Fix: "Split into smaller modules. Consider extracting <identified-function> into its own file"

Create `docs/architecture-rules.md` documenting the invariants these rules enforce. Add to `docs/INDEX.md`.

**TDD phases:**

RED:
```bash
cat > /tmp/test-us007.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: All three rules exist
for rule in dependency-direction naming-conventions file-size-limit; do
    test -x "scripts/lint-rules/${rule}.sh" || { echo "FAIL: ${rule}.sh missing"; exit 1; }
done

# Test 2: naming-conventions catches bad name
mkdir -p /tmp/test-naming
echo '#!/bin/bash' > /tmp/test-naming/badName.sh
! scripts/lint-rules/naming-conventions.sh /tmp/test-naming/badName.sh 2>/dev/null || { echo "FAIL: bad name not caught"; exit 1; }
rm -rf /tmp/test-naming

# Test 3: file-size-limit catches oversized script
python3 -c "print('\n'.join(['echo line'] * 350))" > /tmp/test-big.sh
! scripts/lint-rules/file-size-limit.sh /tmp/test-big.sh 2>/dev/null || { echo "FAIL: big file not caught"; exit 1; }
rm -f /tmp/test-big.sh

# Test 4: architecture-rules.md exists
test -f docs/architecture-rules.md || { echo "FAIL: architecture-rules.md missing"; exit 1; }

# Test 5: INDEX.md references architecture-rules.md
grep -q "architecture-rules.md" docs/INDEX.md || { echo "FAIL: INDEX.md missing architecture-rules.md"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us007.sh
```

GREEN: Implement the rules and documentation.

VERIFY:
```bash
bash /tmp/test-us007.sh
for f in scripts/lint-rules/dependency-direction.sh scripts/lint-rules/naming-conventions.sh scripts/lint-rules/file-size-limit.sh; do
    bash -n "$f"
done
```

**Acceptance criteria:**
- [x] `dependency-direction.sh` enforces layer boundaries
- [x] `naming-conventions.sh` enforces kebab-case naming
- [x] `file-size-limit.sh` enforces line count limits
- [x] All rules output JSON with `fix` instructions
- [x] `docs/architecture-rules.md` documents the invariants
- [x] `docs/INDEX.md` updated

---

- [x] **US-REVIEW-S2**: Sprint 2 Review — Quality & Enforcement (10 min) [depends: US-005, US-006, US-007]

**Review scope:** US-005 through US-007

**Acceptance criteria:**
- [x] Linter framework is modular — new rules can be added without modifying runner
- [x] Every lint error includes actionable `fix` instructions
- [x] verify.sh produces structured JSON compatible with state schemas
- [x] dispatch.sh completion path: detect → verify → write records → wake Athena
- [x] Architecture rules are documented and enforced mechanically
- [x] All scripts pass `bash -n` syntax check

---

## Sprint 3: Flywheel & Self-Improvement

**Goal**: Analysis feeds back into template selection automatically, doc gardening detects stale docs, prompt templates scored by historical success.
**Status:** COMPLETE

---

- [x] **US-008**: Analysis-driven template scoring (20 min)

**Files:**
- Modify: `scripts/analyze-runs.sh` — add template-level metrics
- Create: `state/template-scores.json` — auto-generated scoring data
- Create: `scripts/score-templates.sh` — generates scores from run history

**Context to read first:**
- `scripts/analyze-runs.sh` — current analysis (full file)
- `state/runs/` — sample run records (check for template_name field from US-001)
- `templates/README.md` — available templates

**What to implement:**

Create `scripts/score-templates.sh` that:
- Reads all run records from `state/runs/`
- Groups by `template_name`
- Calculates per-template: success rate, avg duration, avg retries, total uses
- Writes `state/template-scores.json`:
```json
{
  "generated_at": "2026-02-12T20:00:00Z",
  "templates": {
    "bug-fix": { "uses": 12, "success_rate": 0.83, "avg_duration_s": 95, "avg_retries": 1.2 },
    "feature": { "uses": 8, "success_rate": 0.75, "avg_duration_s": 180, "avg_retries": 1.5 },
    "custom": { "uses": 3, "success_rate": 0.33, "avg_duration_s": 240, "avg_retries": 2.0 }
  },
  "recommendation": "Avoid 'custom' template (33% success). Prefer 'bug-fix' template for fix tasks."
}
```
- Outputs human-readable summary to stdout
- Supports `--json` flag for machine output

Update `analyze-runs.sh` to include template breakdown in its output (add a `by_template` section alongside existing `by_agent` and `by_model`).

**TDD phases:**

RED:
```bash
cat > /tmp/test-us008.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: score-templates.sh exists and is executable
test -x scripts/score-templates.sh || { echo "FAIL: score-templates.sh not executable"; exit 1; }

# Test 2: --help works
scripts/score-templates.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: Creates state/template-scores.json when run
scripts/score-templates.sh 2>/dev/null || true
test -f state/template-scores.json || { echo "FAIL: template-scores.json not created"; exit 1; }

# Test 4: Output is valid JSON with templates key
jq -e '.templates' state/template-scores.json || { echo "FAIL: bad template-scores.json structure"; exit 1; }

# Test 5: analyze-runs.sh --json includes by_template
output=$(scripts/analyze-runs.sh --json 2>/dev/null || true)
echo "$output" | jq -e '.statistics.by_template' || { echo "FAIL: analyze-runs.sh missing by_template"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us008.sh
```

GREEN: Implement the scoring script and update analyze-runs.sh.

VERIFY:
```bash
bash /tmp/test-us008.sh
bash -n scripts/score-templates.sh
bash -n scripts/analyze-runs.sh
```

**Acceptance criteria:**
- [x] `scripts/score-templates.sh` generates `state/template-scores.json`
- [x] Scores include success_rate, avg_duration, avg_retries per template
- [x] `analyze-runs.sh` includes `by_template` section
- [x] `--json` flag works for machine consumption
- [x] Recommendation text identifies worst-performing template

---

- [x] **US-009**: Automatic template selection in dispatch (15 min) [depends: US-008]

**Files:**
- Create: `scripts/select-template.sh`
- Modify: `docs/templates-guide.md` — document auto-selection

**Context to read first:**
- `state/template-scores.json` — from US-008
- `templates/` — available templates
- `scripts/dispatch.sh` — current dispatch flow

**What to implement:**

Create `scripts/select-template.sh` that:
- Takes a task description as argument
- Classifies the task type by keyword matching (fix/bug → bug-fix, add/implement/create → feature, refactor/clean → refactor, doc/write → docs, script/build → script)
- Checks `state/template-scores.json` for that template's score
- If score exists and success_rate > 0.5, recommends that template
- If score exists and success_rate <= 0.5, warns and suggests alternatives
- If no score data, recommends the template with a "no data yet" note
- Outputs the recommended template name and path
- Supports `--json` for machine output

This script is called by Athena before dispatch to auto-select the best template. It does NOT modify dispatch.sh directly — it's a decision-support tool.

**TDD phases:**

RED:
```bash
cat > /tmp/test-us009.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: select-template.sh exists and is executable
test -x scripts/select-template.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/select-template.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: Bug-related task selects bug-fix template
output=$(scripts/select-template.sh "Fix the auth timeout bug" 2>&1)
echo "$output" | grep -qi "bug-fix" || { echo "FAIL: bug task didn't select bug-fix"; exit 1; }

# Test 4: Feature task selects feature template
output=$(scripts/select-template.sh "Add user profile page" 2>&1)
echo "$output" | grep -qi "feature" || { echo "FAIL: feature task didn't select feature"; exit 1; }

# Test 5: JSON output is valid
output=$(scripts/select-template.sh --json "Fix something" 2>&1)
echo "$output" | jq -e '.template' || { echo "FAIL: --json output invalid"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us009.sh
```

GREEN: Implement the selection logic.

VERIFY:
```bash
bash /tmp/test-us009.sh
bash -n scripts/select-template.sh
```

**Acceptance criteria:**
- [x] `scripts/select-template.sh` classifies tasks and recommends templates
- [x] Uses historical scores from `state/template-scores.json` when available
- [x] Warns about low-scoring templates
- [x] `--json` flag for machine consumption
- [x] `docs/templates-guide.md` documents the auto-selection flow

---

- [x] **US-010**: Doc gardening agent script (20 min)

**Files:**
- Create: `scripts/doc-gardener.sh`
- Modify: `docs/INDEX.md` — document the gardening process

**Context to read first:**
- `docs/` — all current docs
- `scripts/docs-index.sh` — from US-003 (index consistency)
- `reference/harness-engineering-notes.md` — section 8 on doc gardening
- `VISION.md` — principle 8 (doc gardening is automated hygiene)

**What to implement:**

Create `scripts/doc-gardener.sh` that:
- Scans all docs in `docs/` directory
- For each doc, checks:
  1. **Stale references**: mentions of files that don't exist (e.g., `scripts/foo.sh` when foo.sh was deleted)
  2. **Broken internal links**: references to other docs that don't exist
  3. **Schema drift**: `docs/state-schema.md` matches actual schemas in `state/schemas/`
  4. **Template drift**: `docs/templates-guide.md` lists all templates in `templates/`
- Outputs a JSON report of issues found:
```json
{
  "scanned_at": "...",
  "issues": [
    {"doc": "docs/dispatch-flow.md", "type": "stale-reference", "detail": "references scripts/old.sh which doesn't exist", "suggested_fix": "Remove reference or update path"}
  ],
  "summary": { "total_docs": 6, "docs_with_issues": 1, "total_issues": 1 }
}
```
- Returns exit code 0 if no issues, 1 if issues found
- Supports `--fix` flag that generates a fix prompt for each issue (text that could be given to an agent)
- Has `--help` usage text

**TDD phases:**

RED:
```bash
cat > /tmp/test-us010.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: doc-gardener.sh exists and is executable
test -x scripts/doc-gardener.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/doc-gardener.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: Outputs valid JSON
output=$(scripts/doc-gardener.sh --json 2>&1 || true)
echo "$output" | jq -e '.summary' || { echo "FAIL: output not valid JSON"; exit 1; }

# Test 4: Detects stale reference (inject one)
mkdir -p /tmp/test-docs
echo 'See [deploy script](scripts/deploy-old.sh) for details.' > /tmp/test-docs/test.md
output=$(scripts/doc-gardener.sh --json --docs-dir /tmp/test-docs 2>&1 || true)
echo "$output" | jq -e '.issues | length > 0' || { echo "FAIL: didn't detect stale reference"; exit 1; }
rm -rf /tmp/test-docs

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us010.sh
```

GREEN: Implement the gardening script.

VERIFY:
```bash
bash /tmp/test-us010.sh
bash -n scripts/doc-gardener.sh
```

**Acceptance criteria:**
- [x] `scripts/doc-gardener.sh` scans docs for staleness
- [x] Detects stale file references, broken links, schema drift, template drift
- [x] Outputs structured JSON report
- [x] `--fix` generates agent-ready fix prompts
- [x] Exit code 0 = clean, 1 = issues found

---

- [x] **US-REVIEW-S3**: Sprint 3 Review — Flywheel & Self-Improvement (10 min) [depends: US-008, US-009, US-010]

**Review scope:** US-008 through US-010

**Acceptance criteria:**
- [x] Template scores computed correctly from run data
- [x] Template selection uses real data, not just hardcoded rules
- [x] Doc gardener detects actual drift (test with a real stale doc)
- [x] All scripts follow existing patterns (usage, --help, --json, exit codes)
- [x] The flywheel loop is complete: runs → analysis → scores → selection → better runs
- [x] No circular dependencies between scripts

---

## Sprint 4: Autonomous Operation

**Goal**: Overnight orchestrator, planning layer, calibration system, git worktree isolation.
**Status:** COMPLETE

---

- [x] **US-011**: Git worktree manager for parallel agent isolation (15 min)

**Files:**
- Create: `scripts/worktree-manager.sh`
- Modify: `docs/INDEX.md` — add worktree docs
- Create: `docs/worktree-guide.md`

**Context to read first:**
- `SWARM.md` — "Parallel Work" section
- `VISION.md` — principle 9 (git worktrees enable agent isolation)
- `scripts/dispatch.sh` — how agents are currently launched in a repo path

**What to implement:**

Create `scripts/worktree-manager.sh` that manages git worktrees for parallel agent execution:

Commands:
- `create <bead-id> <repo-path>` — Creates worktree at `<repo-path>/../<repo-name>-wt-<bead-id>`, on branch `bead-<bead-id>`, returns worktree path
- `destroy <bead-id> <repo-path>` — Removes worktree and deletes branch (if merged or force flag)
- `list <repo-path>` — Lists all agent worktrees with status (active/stale)
- `cleanup <repo-path>` — Removes all worktrees where the bead is in terminal state (done/failed/timeout)
- `status <bead-id> <repo-path>` — Shows worktree path, branch, clean/dirty status

Safety:
- Max 6 concurrent worktrees per repo (configurable via `WORKTREE_MAX`)
- Check RAM usage before creating (skip if >90% — configurable via `WORKTREE_RAM_LIMIT`)
- Never delete worktrees with uncommitted changes unless `--force`
- Validate repo-path is a git repo before operating

Create `docs/worktree-guide.md` documenting the worktree lifecycle and how dispatch.sh will use it.

**TDD phases:**

RED:
```bash
cat > /tmp/test-us011.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: worktree-manager.sh exists and is executable
test -x scripts/worktree-manager.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/worktree-manager.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: Create and destroy worktree in a test repo
TEST_REPO="/tmp/test-wt-repo"
rm -rf "$TEST_REPO"
mkdir -p "$TEST_REPO" && cd "$TEST_REPO" && git init && echo "test" > file.txt && git add . && git commit -m "init"
cd -

wt_path=$(scripts/worktree-manager.sh create test-bead-1 "$TEST_REPO" 2>&1 | tail -1)
test -d "$wt_path" || { echo "FAIL: worktree not created at $wt_path"; exit 1; }

# Test 4: List shows the worktree
scripts/worktree-manager.sh list "$TEST_REPO" 2>&1 | grep -q "test-bead-1" || { echo "FAIL: list doesn't show worktree"; exit 1; }

# Test 5: Destroy removes it
scripts/worktree-manager.sh destroy test-bead-1 "$TEST_REPO" --force 2>&1
test ! -d "$wt_path" || { echo "FAIL: worktree not removed"; exit 1; }

rm -rf "$TEST_REPO" "${TEST_REPO}-wt-test-bead-1"
echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us011.sh
```

GREEN: Implement the worktree manager.

VERIFY:
```bash
bash /tmp/test-us011.sh
bash -n scripts/worktree-manager.sh
```

**Acceptance criteria:**
- [x] `create` makes a worktree with correct branch name
- [x] `destroy` removes worktree and branch safely
- [x] `list` shows all agent worktrees
- [x] `cleanup` removes terminal-state worktrees
- [x] Max 6 worktrees enforced
- [x] RAM check before creation
- [x] `docs/worktree-guide.md` documents the lifecycle

---

- [x] **US-012**: Calibration system for accept/reject learning (20 min)

**Files:**
- Create: `scripts/calibrate.sh`
- Create: `state/calibration/` directory
- Create: `state/schemas/calibration.schema.json`
- Create: `docs/calibration-guide.md`
- Modify: `docs/INDEX.md`

**Context to read first:**
- `VISION.md` — "Judgment without the human" (hard problem 1), principle 12 (judgment is earned)
- `state/schemas/run.schema.json` — run record structure
- `state/schemas/result.schema.json` — result record structure
- `scripts/analyze-runs.sh` — existing analysis patterns

**What to implement:**

Create a calibration system that tracks Perttu's accept/reject decisions to teach the system taste.

`scripts/calibrate.sh` commands:
- `record <bead-id> <accept|reject> [reason]` — Records a judgment for a completed bead
- `stats` — Shows accept/reject rates by template, agent, model, task type
- `export --json` — Exports all calibration data
- `patterns` — Identifies patterns (e.g., "reject rate is 60% for codex on feature tasks")

`state/calibration/<bead-id>.json` format:
```json
{
  "schema_version": 1,
  "bead": "bd-xyz",
  "decision": "accept",
  "reason": "Clean implementation, good tests",
  "decided_at": "2026-02-12T20:00:00Z",
  "run_context": {
    "agent": "claude",
    "model": "sonnet",
    "template_name": "feature",
    "duration_seconds": 120,
    "verification_overall": "pass"
  }
}
```

`state/schemas/calibration.schema.json` — JSON Schema for calibration records.

The `record` command:
- Reads the run record for the bead to auto-populate `run_context`
- Validates against schema
- Writes atomically (tmp + mv pattern from dispatch.sh)

The `patterns` command:
- Cross-references calibration data with run records
- Identifies statistically significant patterns:
  - If a template has >3 judgments and reject rate >40%, flag it
  - If an agent type has >3 judgments and reject rate >40%, flag it
- Outputs actionable recommendations

**TDD phases:**

RED:
```bash
cat > /tmp/test-us012.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: calibrate.sh exists and is executable
test -x scripts/calibrate.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/calibrate.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: calibration schema exists
test -f state/schemas/calibration.schema.json || { echo "FAIL: schema missing"; exit 1; }
jq -e '."$schema"' state/schemas/calibration.schema.json || { echo "FAIL: invalid schema"; exit 1; }

# Test 4: Record a calibration (need a fake run record)
mkdir -p state/runs state/calibration
cat > state/runs/bd-cal-test.json << 'JSON'
{"schema_version":1,"bead":"bd-cal-test","agent":"claude","model":"sonnet","repo":"/tmp","prompt":"test","prompt_hash":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","started_at":"2026-01-01T00:00:00Z","finished_at":"2026-01-01T00:01:00Z","duration_seconds":60,"status":"done","attempt":1,"max_retries":2,"session_name":"agent-bd-cal-test","result_file":"state/results/bd-cal-test.json","exit_code":0,"output_summary":null,"failure_reason":null,"template_name":"feature","prompt_full":"test"}
JSON

scripts/calibrate.sh record bd-cal-test accept "Clean code" || { echo "FAIL: record command failed"; exit 1; }
test -f state/calibration/bd-cal-test.json || { echo "FAIL: calibration record not written"; exit 1; }
jq -e '.decision == "accept"' state/calibration/bd-cal-test.json || { echo "FAIL: bad record content"; exit 1; }

# Test 5: stats works
scripts/calibrate.sh stats 2>&1 | grep -qi "accept\|reject\|total" || { echo "FAIL: stats output bad"; exit 1; }

# Cleanup
rm -f state/runs/bd-cal-test.json state/calibration/bd-cal-test.json

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us012.sh
```

GREEN: Implement the calibration system.

VERIFY:
```bash
bash /tmp/test-us012.sh
bash -n scripts/calibrate.sh
```

**Acceptance criteria:**
- [x] `calibrate.sh record` writes validated calibration records
- [x] `calibrate.sh stats` shows accept/reject rates by dimensions
- [x] `calibrate.sh patterns` identifies statistically significant rejection patterns
- [x] Records include `run_context` auto-populated from run records
- [x] Schema validates calibration records
- [x] `docs/calibration-guide.md` explains the calibration workflow

---

- [x] **US-013**: Planning layer — goals to task sequences (20 min)

**Files:**
- Create: `scripts/planner.sh`
- Create: `state/plans/` directory
- Create: `state/schemas/plan.schema.json`
- Create: `docs/planning-guide.md`
- Modify: `docs/INDEX.md`

**Context to read first:**
- `VISION.md` — "Planning, not just execution" (hard problem 2)
- `SWARM.md` — bead lifecycle, decomposition flow
- `templates/` — available task templates
- `scripts/select-template.sh` — from US-009
- `state/template-scores.json` — from US-008

**What to implement:**

Create `scripts/planner.sh` that decomposes a goal into a sequenced task plan:

Commands:
- `create <goal-description> [--repo <path>]` — Generates a plan from a goal
- `show <plan-id>` — Displays a plan
- `list` — Lists all plans with status
- `validate <plan-id>` — Checks plan dependencies are satisfiable

Plan generation logic:
1. Parse the goal description for keywords to identify task types
2. Use `select-template.sh` to map each task to a template
3. Detect dependencies (e.g., "after auth is built" → dependency on auth task)
4. Sequence tasks respecting dependencies (topological sort)
5. Estimate duration from `template-scores.json` avg_duration

Output `state/plans/<plan-id>.json`:
```json
{
  "schema_version": 1,
  "plan_id": "plan-abc123",
  "goal": "Add user authentication with JWT",
  "created_at": "2026-02-12T20:00:00Z",
  "status": "draft",
  "tasks": [
    {
      "task_id": "task-1",
      "title": "Create auth middleware",
      "template": "feature",
      "depends_on": [],
      "estimated_duration_s": 180,
      "description": "Implement JWT middleware..."
    },
    {
      "task_id": "task-2",
      "title": "Add login endpoint",
      "template": "feature",
      "depends_on": ["task-1"],
      "estimated_duration_s": 180,
      "description": "Create /login route..."
    }
  ],
  "total_estimated_s": 360,
  "parallelizable_groups": [["task-1"], ["task-2"]]
}
```

The `validate` command checks:
- No circular dependencies
- All `depends_on` references exist
- Templates referenced exist in `templates/`

**TDD phases:**

RED:
```bash
cat > /tmp/test-us013.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: planner.sh exists and is executable
test -x scripts/planner.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/planner.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: plan schema exists
test -f state/schemas/plan.schema.json || { echo "FAIL: plan schema missing"; exit 1; }
jq -e '."$schema"' state/schemas/plan.schema.json || { echo "FAIL: invalid schema"; exit 1; }

# Test 4: Create a plan
mkdir -p state/plans
plan_output=$(scripts/planner.sh create "Fix the login bug and add session timeout" 2>&1)
echo "$plan_output" | grep -q "plan-" || { echo "FAIL: plan creation failed"; exit 1; }

# Test 5: List shows the plan
scripts/planner.sh list 2>&1 | grep -q "plan-" || { echo "FAIL: list doesn't show plan"; exit 1; }

# Test 6: Plan JSON is valid
plan_file=$(ls state/plans/plan-*.json 2>/dev/null | head -1)
test -n "$plan_file" || { echo "FAIL: no plan file created"; exit 1; }
jq -e '.tasks | length > 0' "$plan_file" || { echo "FAIL: plan has no tasks"; exit 1; }

# Test 7: Validate passes
plan_id=$(basename "$plan_file" .json)
scripts/planner.sh validate "$plan_id" || { echo "FAIL: validate failed on good plan"; exit 1; }

# Cleanup
rm -f state/plans/plan-*.json

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us013.sh
```

GREEN: Implement the planning system.

VERIFY:
```bash
bash /tmp/test-us013.sh
bash -n scripts/planner.sh
```

**Acceptance criteria:**
- [x] `planner.sh create` decomposes goals into sequenced tasks
- [x] Tasks have dependencies and template assignments
- [x] `planner.sh validate` checks dependency graph integrity
- [x] Plans include estimated durations from template scores
- [x] `parallelizable_groups` identifies tasks that can run simultaneously
- [x] `docs/planning-guide.md` documents the planning workflow

---

- [x] **US-014**: Overnight orchestrator (25 min) [depends: US-011, US-012, US-013]

**Files:**
- Create: `scripts/orchestrator.sh`
- Create: `state/orchestrator-log.jsonl` (append-only log)
- Create: `docs/orchestrator-guide.md`
- Modify: `docs/INDEX.md`

**Context to read first:**
- `VISION.md` — "The Dream" section, hard problem 4 (autonomous strategic operation)
- `scripts/dispatch.sh` — how to launch agents
- `scripts/planner.sh` — from US-013
- `scripts/worktree-manager.sh` — from US-011
- `scripts/calibrate.sh` — from US-012
- `scripts/score-templates.sh` — from US-008
- `scripts/verify.sh` — post-completion verification
- `SWARM.md` — the full flow

**What to implement:**

Create `scripts/orchestrator.sh` — the overnight autonomous operator that reads state and makes real decisions.

Modes:
- `run [--max-hours N] [--max-tasks N] [--repo <path>]` — Start autonomous execution
- `dry-run [--repo <path>]` — Show what would be done without executing
- `status` — Show current orchestrator state
- `stop` — Graceful shutdown (finish current tasks, don't start new ones)

The `run` loop:
```
1. Read state: active agents, pending beads, plans, calibration data
2. Score templates (call score-templates.sh)
3. Check calibration patterns (call calibrate.sh patterns)
4. For each pending bead (or plan task):
   a. Select template (call select-template.sh)
   b. If calibration data suggests high reject rate for this type → flag for human review, skip
   c. Create worktree (call worktree-manager.sh create)
   d. Dispatch agent (call dispatch.sh with worktree path)
   e. Log decision to orchestrator-log.jsonl
5. Wait for any agent to complete (poll state/results/)
6. On completion:
   a. Verify results (already done by dispatch.sh)
   b. If verification passes and calibration confidence is high → auto-close bead
   c. If verification fails → retry (dispatch.sh handles this)
   d. If calibration confidence is low → flag for morning review
   e. Cleanup worktree (call worktree-manager.sh destroy)
7. Repeat until: max hours reached, max tasks reached, no more work, or stop signal
```

Safety guardrails:
- Max concurrent agents: 4 (configurable via `ORCH_MAX_AGENTS`)
- Max total runtime: 8 hours (configurable via `ORCH_MAX_HOURS`)
- Max tasks per session: 20 (configurable via `ORCH_MAX_TASKS`)
- If calibration reject rate >50% for a category → skip that category, log reason
- All decisions logged to `state/orchestrator-log.jsonl` with timestamp and reasoning
- `stop` creates a `state/orchestrator-stop` sentinel file that the loop checks

Log format (JSONL, one line per event):
```json
{"ts":"2026-02-12T22:00:00Z","event":"dispatch","bead":"bd-abc","template":"feature","agent":"claude","worktree":"/path","reason":"highest priority pending bead"}
{"ts":"2026-02-12T22:05:00Z","event":"complete","bead":"bd-abc","status":"done","verification":"pass","auto_closed":true}
{"ts":"2026-02-12T22:05:01Z","event":"skip","bead":"bd-def","reason":"calibration reject rate 65% for codex+feature — flagged for human review"}
```

**TDD phases:**

RED:
```bash
cat > /tmp/test-us014.sh << 'TESTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Test 1: orchestrator.sh exists and is executable
test -x scripts/orchestrator.sh || { echo "FAIL: not executable"; exit 1; }

# Test 2: --help works
scripts/orchestrator.sh --help 2>&1 | grep -q "Usage" || { echo "FAIL: --help missing"; exit 1; }

# Test 3: dry-run works without errors
scripts/orchestrator.sh dry-run 2>&1 || { echo "FAIL: dry-run failed"; exit 1; }

# Test 4: status works
scripts/orchestrator.sh status 2>&1 || { echo "FAIL: status failed"; exit 1; }

# Test 5: stop creates sentinel file
scripts/orchestrator.sh stop 2>&1
test -f state/orchestrator-stop || { echo "FAIL: stop sentinel not created"; exit 1; }
rm -f state/orchestrator-stop

# Test 6: orchestrator-guide.md exists
test -f docs/orchestrator-guide.md || { echo "FAIL: guide missing"; exit 1; }

echo "ALL TESTS PASSED"
TESTEOF
bash /tmp/test-us014.sh
```

GREEN: Implement the orchestrator.

VERIFY:
```bash
bash /tmp/test-us014.sh
bash -n scripts/orchestrator.sh
```

**Acceptance criteria:**
- [x] `orchestrator.sh run` executes the autonomous loop
- [x] `dry-run` shows planned actions without executing
- [x] `status` shows current state
- [x] `stop` triggers graceful shutdown via sentinel file
- [x] All decisions logged to `state/orchestrator-log.jsonl`
- [x] Respects max concurrent agents, max hours, max tasks limits
- [x] Skips categories with high calibration reject rate
- [x] Creates worktrees for parallel agents
- [x] Auto-closes beads when calibration confidence is high
- [x] `docs/orchestrator-guide.md` documents the autonomous operation model

---

- [x] **US-REVIEW-S4**: Sprint 4 Review — Autonomous Operation (10 min) [depends: US-011, US-012, US-013, US-014]

**Review scope:** US-011 through US-014

**Acceptance criteria:**
- [x] Worktree manager safely creates/destroys/cleans up worktrees
- [x] Calibration system learns from accept/reject data
- [x] Planner decomposes goals into dependency-aware task sequences
- [x] Orchestrator integrates all components into an autonomous loop
- [x] Safety guardrails prevent runaway operation (max hours, max tasks, RAM check)
- [x] All decisions are logged and auditable
- [x] The system can run unattended for N hours and produce useful work
- [x] `dry-run` mode provides confidence before real execution
- [x] No hardcoded paths (all configurable or relative)
- [x] All scripts follow project conventions (--help, exit codes, --json where applicable)

---

## Summary

| Sprint | Tasks | Focus |
|--------|-------|-------|
| 1 | US-001 to US-004 + review | Rich state, schema enforcement, structured docs |
| 2 | US-005 to US-007 + review | Linter framework, verify integration, architecture rules |
| 3 | US-008 to US-010 + review | Template scoring, auto-selection, doc gardening |
| 4 | US-011 to US-014 + review | Worktrees, calibration, planning, orchestrator |

**Total**: 14 implementation tasks + 4 reviews = 18 items

**Execution**: `./scripts/ralph.sh swarm_vision 25`

**Dependency graph:**
```
US-001 ──→ US-002 ──→ US-004
                          │
US-003 ─────────────────→ REVIEW-S1
                          │
US-005 ──→ US-006         │
     └───→ US-007 ──────→ REVIEW-S2
                          │
US-008 ──→ US-009         │
US-010 ──────────────────→ REVIEW-S3
                          │
US-011 ─────┐             │
US-012 ─────┼──→ US-014 → REVIEW-S4
US-013 ─────┘
```
