#!/usr/bin/env bash
# test-review-agent.sh - Quick sanity test for code review agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Testing code review agent..."
echo

# Test with the latest commit (simulating a bead review)
TEST_BEAD="test-$(date +%s)"

echo "Creating test scenario for bead: $TEST_BEAD"
echo "Using latest commit for diff"
echo

# Run the review
if "$SCRIPT_DIR/review-agent.sh" "$TEST_BEAD"; then
    EXIT_CODE=0
    VERDICT="ACCEPT"
else
    EXIT_CODE=$?
    case $EXIT_CODE in
        1) VERDICT="REJECT" ;;
        2) VERDICT="REVISE" ;;
        *) VERDICT="UNKNOWN ($EXIT_CODE)" ;;
    esac
fi

echo
echo "Review complete!"
echo "Verdict: $VERDICT"
echo "Exit code: $EXIT_CODE"
echo

# Display the results
REVIEW_FILE="$SCRIPT_DIR/../state/reviews/$TEST_BEAD.json"
if [ -f "$REVIEW_FILE" ]; then
    echo "Results:"
    jq '.' "$REVIEW_FILE"
    echo
    echo "Summary:"
    jq -r '.summary' "$REVIEW_FILE"
    echo
    echo "Score: $(jq -r '.score' "$REVIEW_FILE")/10"
    echo "Issues found: $(jq '.issues | length' "$REVIEW_FILE")"

    # Show issues if any
    if [ "$(jq '.issues | length' "$REVIEW_FILE")" -gt 0 ]; then
        echo
        echo "Issues:"
        jq -r '.issues[] | "  [\(.severity | ascii_upcase)] \(.file):\(.line) - \(.description)"' "$REVIEW_FILE"
    fi
else
    echo "Error: Review file not found at $REVIEW_FILE"
    exit 1
fi
