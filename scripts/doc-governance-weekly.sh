#!/usr/bin/env bash
# doc-governance-weekly.sh - Weekly docs + PRD governance sweep

set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

STATE_RESULTS_DIR="$WORKSPACE_ROOT/state/results"
mkdir -p "$STATE_RESULTS_DIR"

DRY_RUN=0
NO_BEAD=0

usage() {
    cat <<EOF
Usage: doc-governance-weekly.sh [OPTIONS]

Run weekly documentation and PRD governance checks.

OPTIONS:
  --help      Show this help message
  --dry-run   Run checks and write reports, skip bead creation
  --no-bead   Skip bead creation even if issues are found
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            NO_BEAD=1
            shift
            ;;
        --no-bead)
            NO_BEAD=1
            shift
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
today="$(date -u +%Y-%m-%d)"
doc_json="$STATE_RESULTS_DIR/doc-gardener-$timestamp.json"
prd_json="$STATE_RESULTS_DIR/prd-lint-$timestamp.json"
report_md="$STATE_RESULTS_DIR/doc-governance-$today.md"

doc_status="pass"
prd_status="pass"

if "$WORKSPACE_ROOT/scripts/doc-gardener.sh" --json > "$doc_json"; then
    doc_status="pass"
else
    doc_status="fail"
fi

if "$WORKSPACE_ROOT/scripts/prd-lint.sh" --json > "$prd_json"; then
    prd_status="pass"
else
    prd_status="fail"
fi

doc_issues="$(jq -r '.summary.total_issues // 0' "$doc_json" 2>/dev/null || echo 0)"
prd_issues="$(jq -r '.summary.total_issues // 0' "$prd_json" 2>/dev/null || echo 0)"
[[ "$doc_issues" =~ ^[0-9]+$ ]] || doc_issues=0
[[ "$prd_issues" =~ ^[0-9]+$ ]] || prd_issues=0
total_issues=$((doc_issues + prd_issues))

bead_id=""
if (( total_issues > 0 )) && (( NO_BEAD == 0 )) && command -v bd >/dev/null 2>&1; then
    bead_title="[docs] Weekly governance drift $today"
    bead_description="doc-gardener issues: $doc_issues, prd-lint issues: $prd_issues. See $report_md."
    bead_output="$(bd create --title "$bead_title" --description "$bead_description" --priority 1 --issue-type chore --json 2>/dev/null || true)"
    if [[ -n "$bead_output" ]]; then
        bead_id="$(printf '%s' "$bead_output" | jq -r '.id // .bead // empty' 2>/dev/null || true)"
        if [[ -z "$bead_id" ]]; then
            bead_id="$(printf '%s' "$bead_output" | grep -Eo 'bd-[a-z0-9-]+' | head -n 1 || true)"
        fi
    fi
fi

{
    echo "# Weekly Documentation Governance Report"
    echo ""
    echo "- Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- doc-gardener: $doc_status ($doc_issues issues)"
    echo "- prd-lint: $prd_status ($prd_issues issues)"
    echo "- total issues: $total_issues"
    echo "- dry-run: $DRY_RUN"
    if [[ -n "$bead_id" ]]; then
        echo "- created bead: $bead_id"
    elif (( total_issues > 0 )); then
        echo "- created bead: no"
    fi
    echo ""
    echo "## Artifacts"
    echo ""
    echo "- $doc_json"
    echo "- $prd_json"
    echo ""
    echo "## Next Action"
    echo ""
    if (( total_issues == 0 )); then
        echo "No action required."
    else
        echo "Fix issues reported by doc-gardener and prd-lint before next dispatch cycle."
    fi
} > "$report_md"

echo "$report_md"

if (( total_issues == 0 )); then
    exit 0
fi
exit 1
