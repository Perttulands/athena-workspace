#!/usr/bin/env bash
# Example: Integrate doc-gardener with Athena overnight orchestrator
# This demonstrates how to use doc-gardener in automated workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_GARDENER="$SCRIPT_DIR/../doc-gardener.sh"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MEMORY_DIR="$WORKSPACE_DIR/memory"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="$MEMORY_DIR/$TODAY.md"

# Configuration
DOC_QUALITY_THRESHOLD=7.0
CREATE_BEAD_ON_FAILURE=true

log() {
    echo "[$(date +%H:%M:%S)] $*"
}

log_memory() {
    echo "- [$(date +%H:%M:%S)] $*" >> "$MEMORY_FILE"
}

# Run documentation audit
log "Starting documentation quality check..."
log_memory "Doc-gardener: Starting workspace audit"

if ! AUDIT_JSON="$("$DOC_GARDENER" --workspace --format json)"; then
    log "ERROR: Doc-gardener execution failed"
    log_memory "Doc-gardener: FAILED - execution error"
    exit 1
fi

if [[ -z "$AUDIT_JSON" ]]; then
    log "ERROR: Doc-gardener failed to produce output"
    log_memory "Doc-gardener: FAILED - no output"
    exit 1
fi

# Extract key metrics
AUDIT_ID=$(echo "$AUDIT_JSON" | jq -r '.audit_id')
OVERALL_SCORE=$(echo "$AUDIT_JSON" | jq -r '.overall_score')
DOCS_REVIEWED=$(echo "$AUDIT_JSON" | jq -r '.documents_reviewed')
MAJOR_ISSUES=$(echo "$AUDIT_JSON" | jq -r '[.findings[] | select(.severity == "major")] | length')
MINOR_ISSUES=$(echo "$AUDIT_JSON" | jq -r '[.findings[] | select(.severity == "minor")] | length')

log "Audit complete: $AUDIT_ID"
log "  Score: $OVERALL_SCORE/10"
log "  Documents reviewed: $DOCS_REVIEWED"
log "  Major issues: $MAJOR_ISSUES"
log "  Minor issues: $MINOR_ISSUES"

log_memory "Doc-gardener: Score $OVERALL_SCORE/10 ($MAJOR_ISSUES major, $MINOR_ISSUES minor issues)"

# Check if score meets threshold
if (( $(echo "$OVERALL_SCORE < $DOC_QUALITY_THRESHOLD" | bc -l) )); then
    log "WARNING: Documentation quality below threshold ($DOC_QUALITY_THRESHOLD)"
    log_memory "Doc-gardener: BELOW THRESHOLD - score $OVERALL_SCORE < $DOC_QUALITY_THRESHOLD"

    if [[ "$CREATE_BEAD_ON_FAILURE" == true ]]; then
        log "Creating remediation bead..."

        # Extract high-priority improvements
        PRIORITIES=$(echo "$AUDIT_JSON" | jq -r '.improvement_priorities[] | select(.priority == "high") | "- \(.area) (effort: \(.effort))"')

        # Create bead description
        BEAD_DESC="Fix documentation quality issues (score: $OVERALL_SCORE/10)

High-priority improvements:
$PRIORITIES

Major issues found: $MAJOR_ISSUES
Minor issues found: $MINOR_ISSUES

Full audit: state/doc-audits/$AUDIT_ID.json"

        # Create bead using bd CLI
        if command -v bd &>/dev/null; then
            BEAD_ID=$(bd create \
                --title "Documentation quality remediation" \
                --description "$BEAD_DESC" \
                --priority P2 \
                --labels doc-quality,automated \
                --json | jq -r '.id')

            log "Created bead: $BEAD_ID"
            log_memory "Doc-gardener: Created remediation bead $BEAD_ID"

            # Attach audit file to bead
            if ! bd update "$BEAD_ID" --notes "Audit file: $WORKSPACE_DIR/state/doc-audits/$AUDIT_ID.json"; then
                log "WARNING: failed to attach audit file to bead $BEAD_ID"
                log_memory "Doc-gardener: Could not attach audit file to bead $BEAD_ID"
            fi
        else
            log "WARNING: bd command not found, cannot create bead"
            log_memory "Doc-gardener: Cannot create bead (bd not found)"
        fi
    fi
else
    log "✓ Documentation quality meets threshold"
    log_memory "Doc-gardener: PASS - score $OVERALL_SCORE >= $DOC_QUALITY_THRESHOLD"
fi

# Report high-priority findings to Athena's attention
if [[ $MAJOR_ISSUES -gt 0 ]]; then
    log ""
    log "Major issues requiring attention:"
    echo "$AUDIT_JSON" | jq -r '.findings[] | select(.severity == "major") | "  • \(.file): \(.issue)"' | head -5
fi

# Success
exit 0
