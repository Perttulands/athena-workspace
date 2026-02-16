#!/usr/bin/env bash
# doc-gardener.sh - Detect stale documentation and drift between docs and code

set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -v DOCS_DIR ]]; then
    DOCS_DIR="${DOCS_DIR:?DOCS_DIR cannot be empty}"
else
    DOCS_DIR="$WORKSPACE_ROOT/docs"
fi
TEMPLATES_DIR="$WORKSPACE_ROOT/templates"
SCHEMAS_DIR="$WORKSPACE_ROOT/state/schemas"
SCRIPTS_DIR="$WORKSPACE_ROOT/scripts"

usage() {
    cat <<EOF
Usage: doc-gardener.sh [OPTIONS]

Scans documentation for staleness and drift from actual code.

OPTIONS:
  --help           Show this help message
  --json           Output JSON report (default: human-readable)
  --docs-dir DIR   Scan specific docs directory (default: docs/)
  --fix            Generate fix prompts for each issue

EXIT CODES:
  0    No issues found
  1    Issues detected

CHECKS:
  - Stale file references (mentions files that don't exist)
  - Broken internal doc links
  - Schema drift (docs/state-schema.md vs actual schemas)
  - Template drift (docs/templates-guide.md vs actual templates)

EXAMPLES:
  ./scripts/doc-gardener.sh
  ./scripts/doc-gardener.sh --json
  ./scripts/doc-gardener.sh --fix
EOF
}

# Parse arguments
JSON_OUTPUT=0
FIX_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --fix)
            FIX_MODE=1
            shift
            ;;
        --docs-dir)
            DOCS_DIR="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

# Check directories exist
if [[ ! -d "$DOCS_DIR" ]]; then
    echo "Error: Docs directory not found at $DOCS_DIR" >&2
    exit 1
fi

# Initialize issues array
declare -a issues=()

# Function to add an issue
add_issue() {
    local doc="$1"
    local issue_type="$2"
    local detail="$3"
    local fix="$4"

    issues+=("{\"doc\":\"$doc\",\"type\":\"$issue_type\",\"detail\":\"$detail\",\"suggested_fix\":\"$fix\"}")
}

# Check 1: Stale file references in docs
check_stale_references() {
    local doc="$1"

    # Extract references to script files: scripts/foo.sh, state/bar.json, etc.
    # Match patterns like: scripts/xyz.sh, state/schemas/abc.json
    local ref_patterns=(
        'scripts/[a-zA-Z0-9_-]+\.sh'
        'state/schemas/[a-zA-Z0-9_-]+\.json'
        'templates/[a-zA-Z0-9_-]+\.md'
    )

    for pattern in "${ref_patterns[@]}"; do
        while IFS= read -r ref; do
            # Check if referenced file exists
            local file_path="$WORKSPACE_ROOT/$ref"
            if [[ ! -f "$file_path" ]]; then
                local detail="references $ref which doesn't exist"
                local fix="Remove reference or update path to correct file"
                add_issue "$doc" "stale-reference" "$detail" "$fix"
            fi
        done < <(grep -oE "$pattern" "$DOCS_DIR/$doc")
    done
}

# Check 2: Broken internal doc links
check_broken_links() {
    local doc="$1"

    # Extract markdown links: [text](filename.md) or [text](path/to/file.md)
    local regex='\]\(([^)]+\.md)\)'

    while IFS= read -r line; do
        if [[ "$line" =~ $regex ]]; then
            local link_target="${BASH_REMATCH[1]}"

            # Handle both relative and absolute-from-docs paths
            local target_file
            if [[ "$link_target" =~ ^/ ]]; then
                target_file="$WORKSPACE_ROOT${link_target}"
            else
                target_file="$DOCS_DIR/$link_target"
            fi

            if [[ ! -f "$target_file" ]]; then
                local detail="broken link to $link_target"
                local fix="Update link to correct file or create missing doc"
                add_issue "$doc" "broken-link" "$detail" "$fix"
            fi
        fi
    done < "$DOCS_DIR/$doc"
}

# Check 3: Schema drift - docs/state-schema.md should reference actual schemas
check_schema_drift() {
    if [[ ! -f "$DOCS_DIR/state-schema.md" ]]; then
        return
    fi

    # List actual schemas
    mapfile -t actual_schemas < <(find "$SCHEMAS_DIR" -name "*.json" -exec basename {} \; | sort)

    # Check each schema is mentioned in state-schema.md
    for schema in "${actual_schemas[@]}"; do
        if ! grep -q "$schema" "$DOCS_DIR/state-schema.md"; then
            local detail="Schema $schema exists but not documented in state-schema.md"
            local fix="Add documentation for $schema to docs/state-schema.md"
            add_issue "docs/state-schema.md" "schema-drift" "$detail" "$fix"
        fi
    done
}

# Check 4: Template drift - docs/templates-guide.md should list all templates
check_template_drift() {
    if [[ ! -f "$DOCS_DIR/templates-guide.md" ]]; then
        return
    fi

    # List actual templates (excluding README.md)
    mapfile -t actual_templates < <(find "$TEMPLATES_DIR" -name "*.md" ! -name "README.md" -exec basename {} \; | sort)

    # Check each template is mentioned in templates-guide.md
    for template in "${actual_templates[@]}"; do
        if ! grep -q "$template" "$DOCS_DIR/templates-guide.md"; then
            local detail="Template $template exists but not documented in templates-guide.md"
            local fix="Add $template to the template list in docs/templates-guide.md"
            add_issue "docs/templates-guide.md" "template-drift" "$detail" "$fix"
        fi
    done
}

# Scan all .md files in docs/
mapfile -t doc_files < <(find "$DOCS_DIR" -maxdepth 1 -name "*.md" -exec basename {} \; | sort)
total_docs=${#doc_files[@]}

# Run checks on each doc
for doc in "${doc_files[@]}"; do
    check_stale_references "$doc"
    check_broken_links "$doc"
done

# Run cross-cutting checks
check_schema_drift
check_template_drift

# Count issues
total_issues=${#issues[@]}
docs_with_issues=$(printf '%s\n' "${issues[@]}" | jq -r '.doc' | sort -u | wc -l || echo 0)

# Generate output
scanned_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ $JSON_OUTPUT -eq 1 ]]; then
    # JSON output
    issues_json=$(printf '%s\n' "${issues[@]}" | jq -s '.')
    jq -n \
        --arg scanned_at "$scanned_at" \
        --argjson issues "$issues_json" \
        --argjson total_docs "$total_docs" \
        --argjson docs_with_issues "$docs_with_issues" \
        --argjson total_issues "$total_issues" \
        '{
            scanned_at: $scanned_at,
            issues: $issues,
            summary: {
                total_docs: $total_docs,
                docs_with_issues: $docs_with_issues,
                total_issues: $total_issues
            }
        }'
else
    # Human-readable output
    echo "Doc Gardener Report"
    echo "==================="
    echo "Scanned: $total_docs docs at $scanned_at"
    echo ""

    if [[ $total_issues -eq 0 ]]; then
        echo "✓ No issues found. Docs are healthy!"
    else
        echo "✗ Found $total_issues issues in $docs_with_issues docs:"
        echo ""

        # Group by doc
        for doc in $(printf '%s\n' "${issues[@]}" | jq -r '.doc' | sort -u); do
            echo "[$doc]"
            printf '%s\n' "${issues[@]}" | jq -r "select(.doc == \"$doc\") | \"  - [\(.type)] \(.detail)\""

            if [[ $FIX_MODE -eq 1 ]]; then
                echo "  Fixes:"
                printf '%s\n' "${issues[@]}" | jq -r "select(.doc == \"$doc\") | \"    → \(.suggested_fix)\""
            fi
            echo ""
        done
    fi
fi

# Exit code
if [[ $total_issues -eq 0 ]]; then
    exit 0
else
    exit 1
fi
