#!/usr/bin/env bash
# Test: dispatch.sh full lifecycle — create bead, dispatch trivial task, wait for completion, verify results
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_NAME="dispatch-lifecycle"
BEAD_ID=""
TEST_REPO=""
TMUX_SOCKET="/tmp/openclaw-e2e-test.sock"

cleanup() {
    [[ -n "$BEAD_ID" ]] && {
        if ! bd delete "$BEAD_ID" --force >/dev/null 2>&1; then
            echo "WARN: cleanup failed to delete bead $BEAD_ID" >&2
        fi
        rm -f "$WORKSPACE/state/runs/$BEAD_ID.json" \
              "$WORKSPACE/state/results/$BEAD_ID.json" \
              "$WORKSPACE/state/results/${BEAD_ID}-verify.json" \
              "$WORKSPACE/state/watch/$BEAD_ID".*
    }
    [[ -n "$TEST_REPO" ]] && rm -rf "$TEST_REPO"
    if ! tmux -S "$TMUX_SOCKET" kill-server 2>/dev/null; then  # REASON: isolated test socket may already be gone by cleanup time.
        :
    fi
}
trap cleanup EXIT

begin "$TEST_NAME"

# Check codex is available
command -v codex >/dev/null 2>&1 || { echo -e "${YELLOW}⊘ SKIP: $TEST_NAME — codex not found${NC}"; exit 0; }

# Create test repo
TEST_REPO="$(mktemp -d /tmp/e2e-dispatch-XXXXXX)"
cd "$TEST_REPO"
git init -q
echo "# test" > README.md
git add . && git commit -q -m "init"

# Create bead
BEAD_ID="$(bd q "e2e-dispatch-test-$(date +%s)")"
assert_not_empty "$BEAD_ID" "bead created"

# Dispatch with isolated tmux socket and short timeout
export DISPATCH_TMUX_SOCKET="$TMUX_SOCKET"
export DISPATCH_WATCH_INTERVAL="5"
export DISPATCH_WATCH_TIMEOUT="120"

"$WORKSPACE/scripts/dispatch.sh" "$BEAD_ID" "$TEST_REPO" codex \
    "Create a file called hello.txt containing exactly 'hello world'. Nothing else." \
    2>&1 || fail "$TEST_NAME" "dispatch.sh failed to launch"

echo "  Waiting for agent completion (up to 120s)..."
DEADLINE=$((SECONDS + 120))
while (( SECONDS < DEADLINE )); do
    if [[ -f "$WORKSPACE/state/results/$BEAD_ID.json" ]]; then
        STATUS="$(jq -r '.status' "$WORKSPACE/state/results/$BEAD_ID.json")"
        if [[ "$STATUS" == "done" || "$STATUS" == "failed" || "$STATUS" == "timeout" ]]; then
            break
        fi
    fi
    sleep 5
done

# Verify result record exists
RESULT_FILE="$WORKSPACE/state/results/$BEAD_ID.json"
assert_file_exists "$RESULT_FILE" "result record created"

# Verify run record exists
RUN_FILE="$WORKSPACE/state/runs/$BEAD_ID.json"
assert_file_exists "$RUN_FILE" "run record created"

# Check status
RESULT_STATUS="$(jq -r '.status' "$RESULT_FILE")"
echo "  Agent finished with status: $RESULT_STATUS"

# We accept done or failed — the test verifies the pipeline works, not that codex succeeds
[[ "$RESULT_STATUS" == "done" || "$RESULT_STATUS" == "failed" || "$RESULT_STATUS" == "timeout" ]] || \
    fail "$TEST_NAME" "unexpected status: $RESULT_STATUS"

# Verify JSON structure
jq -e '.bead and .agent and .model and .status' "$RESULT_FILE" >/dev/null 2>&1 || \
    fail "$TEST_NAME" "result record missing required fields"
jq -e '.bead and .agent and .model and .status' "$RUN_FILE" >/dev/null 2>&1 || \
    fail "$TEST_NAME" "run record missing required fields"

pass "$TEST_NAME"
