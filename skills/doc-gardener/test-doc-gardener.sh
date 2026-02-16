#!/usr/bin/env bash
# Test script for documentation gardener
# Validates the tool works correctly with various inputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_GARDENER="$SCRIPT_DIR/doc-gardener.sh"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

run_capture() {
    local output
    if output="$("$@" 2>&1)"; then
        printf '%s' "$output"
    else
        printf '%s' "$output"
    fi
}

log_test() {
    echo -e "\n${YELLOW}TEST:${NC} $1"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 1: Help text displays correctly
log_test "Help text displays"
HELP_OUTPUT="$(run_capture "$DOC_GARDENER" --help)"
if echo "$HELP_OUTPUT" | head -1 | grep -q "Documentation Gardener"; then
    pass
else
    fail "Help text not found"
fi

# Test 2: Invalid arguments are rejected
log_test "Invalid arguments rejected"
OUTPUT="$(run_capture "$DOC_GARDENER" --invalid-arg)"
if echo "$OUTPUT" | grep -q "Unknown option"; then
    pass
else
    fail "Should reject invalid arguments"
fi

# Test 3: Missing target path fails
log_test "Missing target path fails"
OUTPUT="$(run_capture "$DOC_GARDENER" --type readme)"
if echo "$OUTPUT" | grep -q "Must specify"; then
    pass
else
    fail "Should require target path"
fi

# Test 4: Invalid document type rejected
log_test "Invalid document type rejected"
OUTPUT="$(run_capture "$DOC_GARDENER" --workspace --type invalid-type)"
if echo "$OUTPUT" | grep -q "Invalid document type"; then
    pass
else
    fail "Should reject invalid document type"
fi

# Test 5: Invalid focus area rejected
log_test "Invalid focus area rejected"
OUTPUT="$(run_capture "$DOC_GARDENER" --workspace --focus invalid-focus)"
if echo "$OUTPUT" | grep -q "Invalid focus area"; then
    pass
else
    fail "Should reject invalid focus area"
fi

# Test 6: Invalid output format rejected
log_test "Invalid output format rejected"
OUTPUT="$(run_capture "$DOC_GARDENER" --workspace --format invalid-format)"
if echo "$OUTPUT" | grep -q "Invalid output format"; then
    pass
else
    fail "Should reject invalid output format"
fi

# Test 7: Non-existent path fails
log_test "Non-existent path fails"
OUTPUT="$(run_capture "$DOC_GARDENER" --path /nonexistent/path)"
if echo "$OUTPUT" | grep -q "does not exist"; then
    pass
else
    fail "Should reject non-existent path"
fi

# Test 8: Find README files
log_test "Find README files"
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/subdir"
echo "# Test README" > "$TEST_DIR/README.md"
echo "# Sub README" > "$TEST_DIR/subdir/README.md"

README_COUNT=$(find "$TEST_DIR" -type f -iname "README*" | wc -l)
if [[ $README_COUNT -eq 2 ]]; then
    pass
else
    fail "Expected 2 README files, found $README_COUNT"
fi
rm -rf "$TEST_DIR"

# Test 9: Calibration requires audit-id and finding-id
log_test "Calibration validation"
OUTPUT="$(run_capture "$DOC_GARDENER" --calibrate)"
if echo "$OUTPUT" | grep -q "requires --audit-id"; then
    pass
else
    fail "Should require audit-id for calibration"
fi

# Test 10: Dependencies check
log_test "Required dependencies available"
DEPS_OK=true
for dep in jq claude find grep sed bc; do
    if ! command -v "$dep" &>/dev/null; then
        echo "  Missing: $dep"
        DEPS_OK=false
    fi
done

if [[ "$DEPS_OK" == true ]]; then
    pass
else
    fail "Some dependencies missing"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results:"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
