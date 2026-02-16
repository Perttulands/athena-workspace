#!/usr/bin/env bash
# Test: truthsayer scan runs and produces valid JSON output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRUTHSAYER_BIN="${TRUTHSAYER_BIN:-/home/perttu/truthsayer/truthsayer}"

TEST_NAME="truthsayer-scan"
begin "$TEST_NAME"

# Check truthsayer exists
if [[ ! -x "$TRUTHSAYER_BIN" ]]; then
    echo -e "${YELLOW}⊘ SKIP: $TEST_NAME — truthsayer not found at $TRUTHSAYER_BIN${NC}"
    exit 0
fi

# Run scan on workspace scripts
SCAN_RC=0
if ! OUTPUT="$("$TRUTHSAYER_BIN" scan --format json "$WORKSPACE/scripts" 2>&1)"; then
    SCAN_RC=$?
fi
assert_not_empty "$OUTPUT" "truthsayer produced output"
if [[ $SCAN_RC -ne 0 ]]; then
    echo "  truthsayer scan exited with code $SCAN_RC (findings may be present)"
fi

# Validate JSON structure
echo "$OUTPUT" | jq -e '.summary' >/dev/null 2>&1 || fail "$TEST_NAME" "output missing .summary field"
echo "$OUTPUT" | jq -e '.summary.errors | type == "number"' >/dev/null 2>&1 || fail "$TEST_NAME" ".summary.errors not a number"
echo "$OUTPUT" | jq -e '.summary.warnings | type == "number"' >/dev/null 2>&1 || fail "$TEST_NAME" ".summary.warnings not a number"

pass "$TEST_NAME"
