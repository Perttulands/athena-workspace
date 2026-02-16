#!/usr/bin/env bash
# docs-index.sh - Detect drift between docs/INDEX.md and actual doc files

set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
DOCS_DIR="$WORKSPACE_ROOT/docs"
INDEX_FILE="$DOCS_DIR/INDEX.md"

usage() {
    cat <<EOF
Usage: docs-index.sh [OPTIONS]

Checks consistency between docs/INDEX.md and actual .md files in docs/.

OPTIONS:
  --help    Show this help message

EXIT CODES:
  0    All docs are listed in INDEX.md, no drift detected
  1    Drift detected (unlisted docs or dead links)

EXAMPLES:
  ./scripts/docs-index.sh
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

# Check docs/ exists
if [[ ! -d "$DOCS_DIR" ]]; then
    echo "Error: docs/ directory not found at $DOCS_DIR" >&2
    exit 1
fi

# Check INDEX.md exists
if [[ ! -f "$INDEX_FILE" ]]; then
    echo "Error: INDEX.md not found at $INDEX_FILE" >&2
    exit 1
fi

# Find all .md files in docs/ (excluding INDEX.md itself)
mapfile -t actual_docs < <(find "$DOCS_DIR" -maxdepth 1 -name "*.md" ! -name "INDEX.md" -exec basename {} \; | sort)

# Check each actual doc is referenced in INDEX.md
drift_detected=0
for doc in "${actual_docs[@]}"; do
    if ! grep -q "$doc" "$INDEX_FILE"; then
        echo "DRIFT: $doc exists but not listed in INDEX.md"
        drift_detected=1
    fi
done

# Check each reference in INDEX.md points to an existing file
regex=']\(([^)]+\.md)\)'
while IFS= read -r line; do
    # Extract markdown links: [text](filename.md)
    if [[ "$line" =~ $regex ]]; then
        link_target="${BASH_REMATCH[1]}"
        # Handle relative paths
        if [[ ! -f "$DOCS_DIR/$link_target" ]]; then
            echo "DRIFT: INDEX.md references $link_target which doesn't exist"
            drift_detected=1
        fi
    fi
done < "$INDEX_FILE"

if [[ $drift_detected -eq 0 ]]; then
    echo "OK: docs/ and INDEX.md are consistent"
    exit 0
else
    echo "FAIL: Drift detected between docs/ and INDEX.md"
    exit 1
fi
