#!/usr/bin/env bash
# Example: Git pre-commit hook for documentation validation
# Place in .git/hooks/pre-commit and make executable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_GARDENER="$SCRIPT_DIR/../../skills/doc-gardener/doc-gardener.sh"

# Only run if documentation files changed
CHANGED_DOCS=$(git diff --cached --name-only --diff-filter=ACM | \
    awk '/\.(md|js|ts|sh|py|rs)$/ {print}')

if [[ -z "$CHANGED_DOCS" ]]; then
    # No documentation changes, skip check
    exit 0
fi

echo "Documentation files changed, running quality check..."

# Create temporary directory with only changed files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy changed files to temp directory (preserving structure)
for file in $CHANGED_DOCS; do
    mkdir -p "$TEMP_DIR/$(dirname "$file")"
    cp "$file" "$TEMP_DIR/$file"
done

# Run audit on changed files only
if ! AUDIT_RESULT="$("$DOC_GARDENER" --path "$TEMP_DIR" --format json)"; then
    echo "❌ Doc-gardener execution failed"
    exit 1
fi

OVERALL_SCORE=$(echo "$AUDIT_RESULT" | jq -r '.overall_score // 0')
MAJOR_ISSUES=$(echo "$AUDIT_RESULT" | jq -r '[.findings[] | select(.severity == "major")] | length // 0')

# Require minimum score of 5.0 to commit
MIN_SCORE=5.0

if (( $(echo "$OVERALL_SCORE < $MIN_SCORE" | bc -l) )); then
    echo "❌ Documentation quality too low: $OVERALL_SCORE/10 (minimum: $MIN_SCORE)"
    echo ""
    echo "Major issues found: $MAJOR_ISSUES"
    echo ""
    echo "Run the following to see details:"
    echo "  ./skills/doc-gardener/doc-gardener.sh --path . --type readme"
    echo ""
    echo "To bypass this check (not recommended):"
    echo "  git commit --no-verify"
    exit 1
fi

if [[ $MAJOR_ISSUES -gt 0 ]]; then
    echo "⚠️  Warning: $MAJOR_ISSUES major documentation issue(s) found"
    echo "Score: $OVERALL_SCORE/10 (acceptable)"
    echo ""
    echo "Consider fixing before committing. Run:"
    echo "  ./skills/doc-gardener/doc-gardener.sh --path ."
    # Allow commit but warn
fi

echo "✓ Documentation quality acceptable ($OVERALL_SCORE/10)"
exit 0
