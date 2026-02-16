#!/bin/bash
set -euo pipefail

# file-size-limit.sh - Enforce file size limits to prevent monolithic files

FILE="$1"

# Count lines
if ! lines="$(wc -l < "$FILE")"; then
    lines="0"
fi

# Define limits based on file type
limit=0
file_type=""

filename=$(basename "$FILE")
dir=$(dirname "$FILE")

# Scripts: 300 lines max
if [[ "$FILE" =~ \.sh$ ]] && [[ "$dir" =~ scripts ]]; then
    limit=300
    file_type="script"
fi

# Docs: 150 lines max
if [[ "$FILE" =~ \.md$ ]] && [[ "$dir" =~ docs ]]; then
    limit=150
    file_type="documentation"
fi

# Check if file exceeds limit
if [[ $limit -gt 0 ]] && [[ $lines -gt $limit ]]; then
    # Try to identify functions/sections that could be extracted
    extract_candidates=""

    if [[ "$FILE" =~ \.sh$ ]]; then
        # Find large functions in bash scripts
        large_funcs=$(awk '/^[a-z_]+\(\)/ {fname=$1; start=NR} /^}/ && fname {size=NR-start; if(size>50) print fname " (" size " lines)"; fname=""}' "$FILE" | head -3 | tr '\n' ', ' | sed 's/, $//')
        if [[ -n "$large_funcs" ]]; then
            extract_candidates="Consider extracting these functions: $large_funcs"
        fi
    fi

    if [[ "$FILE" =~ \.md$ ]]; then
        # Find large sections in markdown
        sections=$(grep -n "^##" "$FILE" | head -5 | awk -F: '{print $2}' | tr '\n' ', ' | sed 's/, $//')
        if [[ -n "$sections" ]]; then
            extract_candidates="Consider splitting sections into separate docs: $sections"
        fi
    fi

    fix_msg="Split into smaller modules. File has $lines lines (limit: $limit). $extract_candidates"

    jq -n \
        --arg rule "file-size-limit" \
        --arg file "$FILE" \
        --argjson line 0 \
        --arg message "$file_type file exceeds $limit line limit (current: $lines lines)" \
        --arg fix "$fix_msg" \
        '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
    exit 1
fi

exit 0
