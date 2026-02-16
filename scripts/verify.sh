#!/usr/bin/env bash
set -euo pipefail

# verify.sh — Run verification checks on a repo after agent work
#
# Usage: verify.sh <repo-path> [bead-id]
# Output: JSON to stdout + optional state/results/<bead-id>-verify.json

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <repo-path> [bead-id]" >&2
    exit 1
fi

REPO_PATH="$1"
BEAD_ID="${2:-}"

if [[ ! -d "$REPO_PATH" ]]; then
    echo "Error: Repository path does not exist: $REPO_PATH" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize result object
LINT_RESULT="skipped"
TESTS_RESULT="skipped"
UBS_RESULT="skipped"
TRUTHSAYER_RESULT="skipped"
LINT_DETAILS="null"
TRUTHSAYER_ERRORS=0
TRUTHSAYER_WARNINGS=0
OVERALL="pass"

# Ensure test log cleanup on exit
TEST_LOG="/tmp/verify-tests-$$.log"
cleanup() { rm -f "$TEST_LOG"; }
trap cleanup EXIT

# ── Check 1: Lint changed files ──────────────────────────────────────────────

if git -C "$REPO_PATH" rev-parse --git-dir > /dev/null 2>&1; then
    CHANGED_FILES=""
    if ! CHANGED_FILES="$(git -C "$REPO_PATH" diff --name-only HEAD 2>&1)"; then
        CHANGED_FILES=""
    fi
    if [[ -n "$CHANGED_FILES" ]] && [[ -x "$SCRIPT_DIR/lint-agent.sh" ]]; then
        LINT_OUTPUT=""
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            if [[ -f "$REPO_PATH/$file" ]]; then
                if LINT_OUTPUT=$("$SCRIPT_DIR/lint-agent.sh" --json "$REPO_PATH/$file" 2>&1); then
                    if [[ "$LINT_RESULT" != "fail" ]]; then
                        LINT_RESULT="pass"
                    fi
                else
                    LINT_RESULT="fail"
                    OVERALL="fail"
                    if [[ "$LINT_DETAILS" == "null" ]]; then
                        LINT_DETAILS="$LINT_OUTPUT"
                    else
                        LINT_DETAILS=$(printf '%s\n%s' "$LINT_DETAILS" "$LINT_OUTPUT" | jq -s 'add' 2>/dev/null) || true
                    fi
                fi
            fi
        done <<< "$CHANGED_FILES"
    elif [[ -n "$CHANGED_FILES" ]] && [[ ! -x "$SCRIPT_DIR/lint-agent.sh" ]]; then
        LINT_RESULT="skipped"
        echo "Warning: lint-agent.sh not found or not executable, skipping lint" >&2
    fi
fi

# ── Check 2: Run tests ──────────────────────────────────────────────────────

# Auto-detect test runner and run with timeout
run_test_check() {
    local repo="$1"
    local test_timeout=120

    if [[ -f "$repo/package.json" ]]; then
        if ! command -v npm >/dev/null 2>&1; then
            echo "Warning: npm not found, skipping tests" >&2
            TESTS_RESULT="skipped"
            return
        fi
        # Use configured timeout or check for long test suites
        if (cd "$repo" && timeout "$test_timeout" npm test) > "$TEST_LOG" 2>&1; then
            TESTS_RESULT="pass"
        else
            local ec=$?
            if [[ $ec -eq 124 ]]; then
                TESTS_RESULT="timeout"
                echo "Warning: tests timed out after ${test_timeout}s" >&2
            else
                TESTS_RESULT="fail"
            fi
            OVERALL="fail"
            echo "=== TEST FAILURES ===" >&2
            tail -30 "$TEST_LOG" >&2
        fi
    elif [[ -f "$repo/Cargo.toml" ]]; then
        if ! command -v cargo >/dev/null 2>&1; then
            echo "Warning: cargo not found, skipping tests" >&2
            TESTS_RESULT="skipped"
            return
        fi
        if (cd "$repo" && timeout 300 cargo test) > "$TEST_LOG" 2>&1; then
            TESTS_RESULT="pass"
        else
            local ec=$?
            if [[ $ec -eq 124 ]]; then
                TESTS_RESULT="timeout"
                echo "Warning: cargo tests timed out after 300s" >&2
            else
                TESTS_RESULT="fail"
            fi
            OVERALL="fail"
            echo "=== TEST FAILURES ===" >&2
            tail -30 "$TEST_LOG" >&2
        fi
    elif [[ -f "$repo/go.mod" ]]; then
        if ! command -v go >/dev/null 2>&1; then
            # Try common install location
            export PATH="$PATH:/usr/local/go/bin"
            if ! command -v go >/dev/null 2>&1; then
                echo "Warning: go not found, skipping tests" >&2
                TESTS_RESULT="skipped"
                return
            fi
        fi
        if (cd "$repo" && timeout 300 go test ./...) > "$TEST_LOG" 2>&1; then
            TESTS_RESULT="pass"
        else
            local ec=$?
            if [[ $ec -eq 124 ]]; then
                TESTS_RESULT="timeout"
                echo "Warning: go tests timed out after 300s" >&2
            else
                TESTS_RESULT="fail"
            fi
            OVERALL="fail"
            echo "=== TEST FAILURES ===" >&2
            tail -30 "$TEST_LOG" >&2
        fi
    fi
}

run_test_check "$REPO_PATH"

# ── Check 3: Truthsayer ─────────────────────────────────────────────────────

if [[ -v TRUTHSAYER_BIN ]]; then
    TRUTHSAYER_BIN="${TRUTHSAYER_BIN:?TRUTHSAYER_BIN cannot be empty}"
else
    TRUTHSAYER_BIN="$HOME/truthsayer/truthsayer"
fi
if [[ -x "$TRUTHSAYER_BIN" ]]; then
    TS_OUTPUT=""
    if ! TS_OUTPUT=$("$TRUTHSAYER_BIN" scan --format json "$REPO_PATH" 2>&1); then
        TS_OUTPUT=""
    fi
    if [[ -n "$TS_OUTPUT" ]]; then
        if ! TRUTHSAYER_ERRORS="$(printf '%s' "$TS_OUTPUT" | jq '.summary.errors // 0' 2>/dev/null)"; then
            TRUTHSAYER_ERRORS=0
        fi
        if ! TRUTHSAYER_WARNINGS="$(printf '%s' "$TS_OUTPUT" | jq '.summary.warnings // 0' 2>/dev/null)"; then
            TRUTHSAYER_WARNINGS=0
        fi
        if [[ "$TRUTHSAYER_ERRORS" =~ ^[0-9]+$ ]] && [[ "$TRUTHSAYER_ERRORS" -gt 0 ]]; then
            TRUTHSAYER_RESULT="fail"
            OVERALL="fail"
        else
            TRUTHSAYER_RESULT="pass"
        fi
    fi
fi

# ── Check 4: UBS ────────────────────────────────────────────────────────────

if command -v ubs > /dev/null 2>&1; then
    if ubs "$REPO_PATH" > /dev/null 2>&1; then
        UBS_RESULT="clean"
    else
        UBS_RESULT="issues"
        OVERALL="fail"
    fi
fi

# ── Build JSON output ────────────────────────────────────────────────────────

# Ensure numeric types even if jq parsing failed
[[ "$TRUTHSAYER_ERRORS" =~ ^[0-9]+$ ]] || TRUTHSAYER_ERRORS=0
[[ "$TRUTHSAYER_WARNINGS" =~ ^[0-9]+$ ]] || TRUTHSAYER_WARNINGS=0

JSON_OUTPUT=$(jq -n \
    --arg repo "$REPO_PATH" \
    --arg bead "$BEAD_ID" \
    --arg lint "$LINT_RESULT" \
    --arg tests "$TESTS_RESULT" \
    --arg ubs "$UBS_RESULT" \
    --arg truthsayer "$TRUTHSAYER_RESULT" \
    --argjson ts_errors "$TRUTHSAYER_ERRORS" \
    --argjson ts_warnings "$TRUTHSAYER_WARNINGS" \
    --argjson lint_details "$LINT_DETAILS" \
    --arg overall "$OVERALL" \
    '{
        repo: $repo,
        bead: $bead,
        checks: {
            lint: $lint,
            tests: $tests,
            ubs: $ubs,
            truthsayer: $truthsayer,
            truthsayer_errors: $ts_errors,
            truthsayer_warnings: $ts_warnings,
            lint_details: $lint_details
        },
        overall: $overall
    }')

echo "$JSON_OUTPUT"

# If bead-id provided, write to state/results/<bead-id>-verify.json
if [[ -n "$BEAD_ID" ]]; then
    RESULTS_DIR="$SCRIPT_DIR/../state/results"
    mkdir -p "$RESULTS_DIR"
    echo "$JSON_OUTPUT" > "$RESULTS_DIR/${BEAD_ID}-verify.json"
fi
