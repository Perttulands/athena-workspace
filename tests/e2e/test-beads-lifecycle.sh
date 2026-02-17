#!/usr/bin/env bash
# Test: beads (bd) create → show → close lifecycle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

TEST_NAME="beads-lifecycle"
BEAD_ID=""

cleanup() {
    if [[ -n "$BEAD_ID" ]]; then
        if ! bd delete "$BEAD_ID" --force >/dev/null 2>&1; then
            echo "WARN: cleanup failed to delete bead $BEAD_ID" >&2
        fi
    fi
}
trap cleanup EXIT

begin "$TEST_NAME"

# Create
BEAD_ID="$(bd q "e2e-test-$(date +%s)")"
assert_not_empty "$BEAD_ID" "bd q returned a bead ID"

# Show
SHOW_OUTPUT="$(bd show "$BEAD_ID")"
assert_contains "$SHOW_OUTPUT" "$BEAD_ID" "bd show contains bead ID"

# Close
bd close "$BEAD_ID"
SHOW_AFTER="$(bd show "$BEAD_ID")"
assert_contains "$SHOW_AFTER" "CLOSED" "bead is closed after bd close"

pass "$TEST_NAME"
