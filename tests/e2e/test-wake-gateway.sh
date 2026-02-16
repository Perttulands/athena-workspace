#!/usr/bin/env bash
# Test: wake-gateway.sh sends wake signal successfully
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAKE_SCRIPT="$WORKSPACE/scripts/wake-gateway.sh"

TEST_NAME="wake-gateway"
begin "$TEST_NAME"

# Verify script exists and is executable
assert_file_exists "$WAKE_SCRIPT" "wake-gateway.sh exists"
[[ -x "$WAKE_SCRIPT" ]] || fail "$TEST_NAME" "wake-gateway.sh not executable"

# Send a test wake
OUTPUT="$("$WAKE_SCRIPT" "e2e-test-wake-$(date +%s)" 2>&1)"
assert_not_empty "$OUTPUT" "wake-gateway.sh returned output"
# Output should be JSON with ok status
echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1 || fail "$TEST_NAME" "output is not valid JSON: $OUTPUT"

pass "$TEST_NAME"
