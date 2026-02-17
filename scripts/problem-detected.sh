#!/usr/bin/env bash
# problem-detected.sh — When a problem is found, create a bead and wake Athena.
# Usage: problem-detected.sh <source> <title> [details]
# Sources: argus, truthsayer, verify, cron, manual
set -euo pipefail

SOURCE="${1:?Usage: problem-detected.sh <source> <title> [details]}"
TITLE="${2:?Title required}"
DETAILS="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create a bead tagged as a problem
BEAD_OUTPUT=$(bd create --title "[$SOURCE] $TITLE" --priority 1 2>&1 | head -1)
BEAD_ID=$(echo "$BEAD_OUTPUT" | grep -oP 'bd-\w+' || echo "unknown")

# Log to problem registry
REGISTRY="$SCRIPT_DIR/../state/problems.jsonl"
mkdir -p "$(dirname "$REGISTRY")"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -cn --arg ts "$TIMESTAMP" --arg source "$SOURCE" --arg bead "$BEAD_ID" \
    --arg title "$TITLE" --arg details "$DETAILS" \
    '{ts:$ts,source:$source,bead:$bead,title:$title,details:$details}' >> "$REGISTRY"

# Wake Athena
if [[ -x "$SCRIPT_DIR/wake-gateway.sh" ]]; then
    "$SCRIPT_DIR/wake-gateway.sh" \
        "Problem detected by $SOURCE: $TITLE (bead: $BEAD_ID)" \
        >/dev/null 2>&1 || true  # REASON: wake is best-effort, bead is the record
fi

echo "$BEAD_ID"
