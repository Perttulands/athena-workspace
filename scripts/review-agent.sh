#!/usr/bin/env bash
set -euo pipefail

# review-agent.sh - Code review agent wrapper
# Usage: ./scripts/review-agent.sh <bead-id>
# Exit codes: 0=accept, 1=reject, 2=revise

BEAD_ID="${1:?Usage: $0 <bead-id>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
REVIEWS_DIR="$WORKSPACE_DIR/state/reviews"
TEMPLATE="$WORKSPACE_DIR/templates/code-review.md"
REVIEW_OUTPUT="$REVIEWS_DIR/${BEAD_ID}.json"

# Ensure reviews directory exists
mkdir -p "$REVIEWS_DIR"

# Get repository path - default to workspace if not in git worktree
REPO_PATH="$WORKSPACE_DIR"

# Try to find the bead's git branch/commit
# Assuming beads create branches like "bead-<id>" or store commit info
# For now, we'll review the current changes in the repo
# In production, you'd extract the specific commit from bead metadata

# Get the diff - check if there's a bead-specific branch first
if git rev-parse --verify "refs/heads/bead-${BEAD_ID}" >/dev/null 2>&1; then
    # Compare bead branch against main/master
    MAIN_BRANCH="main"
    if origin_head="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then
        MAIN_BRANCH="${origin_head#refs/remotes/origin/}"
    fi
    if ! DIFF="$(git diff "${MAIN_BRANCH}...bead-${BEAD_ID}")"; then
        echo "Warning: failed to diff ${MAIN_BRANCH}...bead-${BEAD_ID}" >&2
        DIFF=""
    fi
    if ! FILES_CHANGED="$(git diff --name-only "${MAIN_BRANCH}...bead-${BEAD_ID}")"; then
        echo "Warning: failed to list changed files for ${MAIN_BRANCH}...bead-${BEAD_ID}" >&2
        FILES_CHANGED=""
    fi
else
    # Fall back to staged changes or recent commit
    if ! DIFF="$(git diff HEAD)"; then
        if ! DIFF="$(git diff --cached)"; then
            DIFF=""
        fi
    fi
    if ! FILES_CHANGED="$(git diff --name-only HEAD)"; then
        if ! FILES_CHANGED="$(git diff --name-only --cached)"; then
            FILES_CHANGED=""
        fi
    fi
fi

# If still no diff, check last commit
if [ -z "$DIFF" ]; then
    if ! DIFF="$(git show HEAD)"; then
        DIFF="No changes found"
    fi
    if ! FILES_CHANGED="$(git show --name-only --pretty="" HEAD)"; then
        FILES_CHANGED=""
    fi
fi

# Check if there are any changes to review
if [ -z "$DIFF" ] || [ "$DIFF" = "No changes found" ]; then
    echo "Error: No changes found for bead $BEAD_ID" >&2
    jq -n --arg bead "$BEAD_ID" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{bead:$bead,verdict:"reject",score:0,summary:"No changes to review",issues:[{severity:"critical",file:"unknown",line:0,description:"No diff found for this bead",fix:"Ensure the bead has committed changes"}],patterns:[],reviewed_at:$ts}' > "$REVIEW_OUTPUT"
    exit 1
fi

# Format files changed as a bulleted list
FILES_LIST=""
if [ -n "$FILES_CHANGED" ]; then
    FILES_LIST=$(echo "$FILES_CHANGED" | sed 's/^/- /')
fi

# Generate timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check if architecture rules exist
ARCH_RULES_NOTE=""
if [ -f "$WORKSPACE_DIR/docs/architecture-rules.md" ]; then
    ARCH_RULES_NOTE="Architecture rules file exists at docs/architecture-rules.md - validate against these rules."
fi

# Generate review prompt from template
REVIEW_PROMPT=$(sed \
    -e "s|{{BEAD_ID}}|$BEAD_ID|g" \
    -e "s|{{REPO_PATH}}|$REPO_PATH|g" \
    -e "s|{{TIMESTAMP}}|$TIMESTAMP|g" \
    -e "s|{{FILES_CHANGED}}|$FILES_LIST|g" \
    "$TEMPLATE")

# Escape the diff for sed (tricky with special chars)
# Instead, use a temp file approach
TEMP_PROMPT=$(mktemp)
echo "$REVIEW_PROMPT" | sed '/{{DIFF}}/,$d' > "$TEMP_PROMPT"
echo "$DIFF" >> "$TEMP_PROMPT"
echo "$REVIEW_PROMPT" | sed '1,/{{DIFF}}/d' >> "$TEMP_PROMPT"

# Add architecture note if needed
if [ -n "$ARCH_RULES_NOTE" ]; then
    echo "" >> "$TEMP_PROMPT"
    echo "$ARCH_RULES_NOTE" >> "$TEMP_PROMPT"
fi

# Run Claude in pipe mode with the review prompt
echo "Reviewing bead $BEAD_ID..." >&2
# Read review model from config (default: opus for judgment tasks)
if [[ -v REVIEW_MODEL ]]; then
    REVIEW_MODEL="${REVIEW_MODEL:?REVIEW_MODEL cannot be empty}"
else
    REVIEW_MODEL="opus"
fi
if ! REVIEW_JSON="$(claude -p --dangerously-skip-permissions --model "$REVIEW_MODEL" < "$TEMP_PROMPT")"; then
    REVIEW_JSON='{"error":"Claude execution failed"}'
fi

# Clean up temp file
rm -f "$TEMP_PROMPT"

# Extract just the JSON from the output (Claude might add text before/after)
# Look for the JSON object boundaries
CLEAN_JSON=$(echo "$REVIEW_JSON" | sed -n '/^{/,/^}/p' | head -1)

# If no valid JSON, create error response
if [ -z "$CLEAN_JSON" ] || ! printf '%s' "$CLEAN_JSON" | jq empty >/dev/null 2>&1; then
    CLEAN_JSON=$(jq -n --arg bead "$BEAD_ID" --arg ts "$TIMESTAMP" \
        '{bead:$bead,verdict:"reject",score:0,summary:"Review failed - invalid output",issues:[{severity:"critical",file:"unknown",line:0,description:"Review agent produced invalid JSON",fix:"Check review agent logs"}],patterns:[],reviewed_at:$ts}')
fi

# Write to output file
echo "$CLEAN_JSON" | jq '.' > "$REVIEW_OUTPUT"

# Extract verdict and determine exit code
VERDICT=$(echo "$CLEAN_JSON" | jq -r '.verdict // "reject"')

echo "Review complete. Verdict: $VERDICT" >&2
echo "Results: $REVIEW_OUTPUT" >&2

case "$VERDICT" in
    accept)
        exit 0
        ;;
    reject)
        exit 1
        ;;
    revise)
        exit 2
        ;;
    *)
        echo "Unknown verdict: $VERDICT, treating as reject" >&2
        exit 1
        ;;
esac
