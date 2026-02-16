#!/usr/bin/env bash
# Test: beads (br) create → show → close lifecycle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

TEST_NAME="beads-lifecycle"
BEAD_ID=""

cleanup() {
    if [[ -n "$BEAD_ID" ]]; then
        if ! br delete "$BEAD_ID" --force >/dev/null 2>&1; then
            echo "WARN: cleanup failed to delete bead $BEAD_ID" >&2
        fi
    fi
}
trap cleanup EXIT

begin "$TEST_NAME"

# Create
BEAD_ID="$(br q "e2e-test-$(date +%s)")"
assert_not_empty "$BEAD_ID" "br q returned a bead ID"

# Show
SHOW_OUTPUT="$(br show "$BEAD_ID")"
assert_contains "$SHOW_OUTPUT" "$BEAD_ID" "br show contains bead ID"

# Close
br close "$BEAD_ID"
SHOW_AFTER="$(br show "$BEAD_ID")"
assert_contains "$SHOW_AFTER" "CLOSED" "bead is closed after br close"

pass "$TEST_NAME"
