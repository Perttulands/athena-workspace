#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH_SCRIPT="$WORKSPACE_ROOT/scripts/dispatch.sh"
RUNS_DIR="$WORKSPACE_ROOT/state/runs"
RESULTS_DIR="$WORKSPACE_ROOT/state/results"
WATCH_DIR="$WORKSPACE_ROOT/state/watch"
TMUX_SOCKET="/tmp/openclaw-coding-agents.sock"

PASSED=0
FAILED=0
STATUS="PASS"
DETAIL=""

BEAD_ID=""
TEST_OUTPUT_FILE=""
BEAD_CLOSED=0
if [[ -v KEEP_ARTIFACTS ]]; then
    KEEP_ARTIFACTS="${KEEP_ARTIFACTS:?KEEP_ARTIFACTS cannot be empty}"
else
    KEEP_ARTIFACTS="0"
fi
if [[ -v E2E_AGENT_TYPE ]]; then
    AGENT_TYPE="${E2E_AGENT_TYPE:?E2E_AGENT_TYPE cannot be empty}"
else
    AGENT_TYPE="codex"
fi

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}

finish() {
    local total=$((PASSED + FAILED))
    if [[ $FAILED -gt 0 ]]; then
        STATUS="FAIL"
    fi
    echo "E2E_RESULT|$STATUS|$PASSED|$total|$DETAIL"
    if [[ "$STATUS" == "FAIL" ]]; then
        exit 1
    fi
}

cleanup() {
    local session_name=""
    if [[ -n "$BEAD_ID" ]]; then
        session_name="agent-$BEAD_ID"
    fi

    if [[ -n "$session_name" ]] && tmux -S "$TMUX_SOCKET" has-session -t "$session_name" >/dev/null 2>&1; then
        if ! tmux -S "$TMUX_SOCKET" kill-session -t "$session_name" >/dev/null 2>&1; then
            echo "WARN: failed to kill tmux session $session_name during cleanup" >&2
        fi
    fi

    if [[ -n "$BEAD_ID" && "$BEAD_CLOSED" -eq 0 ]]; then
        if ! br close "$BEAD_ID" --reason "e2e dispatch cleanup" >/dev/null 2>&1; then
            echo "WARN: failed to close bead $BEAD_ID during cleanup" >&2
        fi
    fi

    if [[ "$KEEP_ARTIFACTS" != "1" ]]; then
        if [[ -n "$TEST_OUTPUT_FILE" ]]; then
            rm -f "$TEST_OUTPUT_FILE"
        fi
        if [[ -n "$BEAD_ID" ]]; then
            rm -f "$RUNS_DIR/$BEAD_ID.json"
            rm -f "$RESULTS_DIR/$BEAD_ID.json"
            rm -f "$WATCH_DIR/$BEAD_ID.status.json"
            rm -f "$WATCH_DIR/$BEAD_ID.prompt.txt"
            rm -f "$WATCH_DIR/$BEAD_ID.runner.sh"
        fi
    fi
}

wait_for_terminal_status() {
    local run_file="$1"
    local timeout_seconds="$2"
    local elapsed=0
    local interval=2

    while (( elapsed < timeout_seconds )); do
        if [[ -f "$run_file" ]]; then
            local status
            if status="$(jq -r '.status // empty' "$run_file" 2>&1)"; then
                :
            else
                status=""
            fi
            case "$status" in
                done|failed|timeout)
                    echo "$status"
                    return 0
                    ;;
            esac
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo "wait-timeout"
    return 1
}

trap cleanup EXIT

echo "== Dispatch Pipeline E2E =="

if [[ "$AGENT_TYPE" != "codex" && "$AGENT_TYPE" != "claude" ]]; then
    fail "E2E_AGENT_TYPE must be codex or claude (got: $AGENT_TYPE)"
    finish
fi

for cmd in br jq tmux "$AGENT_TYPE"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        :
    else
        fail "Required command not found: $cmd"
    fi
done

if [[ ! -x "$DISPATCH_SCRIPT" ]]; then
    fail "Dispatch script missing or not executable: $DISPATCH_SCRIPT"
    finish
fi

if [[ $FAILED -gt 0 ]]; then
    finish
fi

create_err_file="$(mktemp)"
if create_json="$(br create --title "e2e-dispatch-$(date +%s)" --priority 1 --ephemeral --json 2>"$create_err_file")"; then
    :
else
    create_json=""
fi
if BEAD_ID="$(printf '%s' "$create_json" | jq -r '.id // empty')"; then
    :
else
    BEAD_ID=""
fi
if [[ -s "$create_err_file" ]]; then
    echo "WARN: br create stderr: $(cat "$create_err_file")" >&2
fi
rm -f "$create_err_file"
if [[ -n "$BEAD_ID" ]]; then
    pass "Created test bead with br: $BEAD_ID"
else
    fail "Failed to create test bead with br"
    finish
fi

TEST_OUTPUT_FILE="/tmp/e2e-test-output-${BEAD_ID}.txt"
MARKER="hello-from-${BEAD_ID}"
PROMPT="Run exactly this shell command and then stop: echo '$MARKER' > '$TEST_OUTPUT_FILE'. Do not modify repository files."

dispatch_output=""
if dispatch_output="$("$DISPATCH_SCRIPT" "$BEAD_ID" "$WORKSPACE_ROOT" "$AGENT_TYPE" "$PROMPT" 2>&1)"; then
    pass "Dispatched trivial agent via dispatch.sh ($AGENT_TYPE)"
else
    dispatch_tail="$(printf '%s' "$dispatch_output" | tail -n 1)"
    fail "dispatch.sh returned a non-zero exit code (${dispatch_tail:-no output})"
    DETAIL="dispatch_error=${dispatch_tail:-unknown}"
    finish
fi

RUN_FILE="$RUNS_DIR/$BEAD_ID.json"
RESULT_FILE="$RESULTS_DIR/$BEAD_ID.json"

if terminal_status="$(wait_for_terminal_status "$RUN_FILE" 300)"; then
    :
else
    terminal_status="wait-timeout"
fi
if [[ "$terminal_status" == "done" ]]; then
    pass "Agent reached terminal done status"
else
    fail "Agent did not finish successfully (status: ${terminal_status:-unknown})"
fi

if [[ -f "$RUN_FILE" ]] && jq -e . "$RUN_FILE" >/dev/null 2>&1; then
    run_status="$(jq -r '.status // empty' "$RUN_FILE")"
    if [[ "$run_status" == "done" ]]; then
        pass "Run record written to state/runs/"
    else
        fail "Run record exists but status is not done (status: $run_status)"
    fi
else
    fail "Run record missing or invalid JSON: $RUN_FILE"
fi

if [[ -f "$RESULT_FILE" ]] && jq -e . "$RESULT_FILE" >/dev/null 2>&1; then
    result_status="$(jq -r '.status // empty' "$RESULT_FILE")"
    if [[ "$result_status" == "done" ]]; then
        pass "Result record written to state/results/"
    else
        fail "Result record exists but status is not done (status: $result_status)"
    fi
else
    fail "Result record missing or invalid JSON: $RESULT_FILE"
fi

if [[ -f "$TEST_OUTPUT_FILE" ]] && grep -qx "$MARKER" "$TEST_OUTPUT_FILE"; then
    pass "Agent produced expected output file"
else
    fail "Expected output not found in $TEST_OUTPUT_FILE"
fi

if br close "$BEAD_ID" --reason "e2e dispatch test complete" >/dev/null 2>&1; then
    BEAD_CLOSED=1
    pass "Closed test bead"
else
    fail "Failed to close test bead: $BEAD_ID"
fi

DETAIL="bead=${BEAD_ID}"
finish
