#!/bin/bash
set -euo pipefail

# json-valid.sh — Validate JSON files with jq
# Reports line-level errors with fix instructions

FILE="$1"

# Only run on JSON files
if [[ ! "$FILE" =~ \.json$ ]]; then
    exit 0
fi

# Try to parse with jq
if ! ERROR_OUTPUT=$(jq empty "$FILE" 2>&1); then
    # Parse failed - extract line number if possible
    LINE=0
    if echo "$ERROR_OUTPUT" | grep -qE 'parse error.*at line [0-9]+'; then
        LINE=$(echo "$ERROR_OUTPUT" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+')
    fi

    # Extract error message
    MESSAGE=$(echo "$ERROR_OUTPUT" | head -1)

    # Generate fix instruction
    FIX="Fix JSON syntax error. Common issues: missing quotes, trailing commas, unescaped characters"

    # Detect specific patterns and provide targeted fix
    if echo "$ERROR_OUTPUT" | grep -q "Expected.*got.*comma"; then
        FIX="Remove trailing comma before closing brace/bracket in JSON"
    elif echo "$ERROR_OUTPUT" | grep -q "Invalid.*escape"; then
        FIX="Fix invalid escape sequence. Use \\\\ for backslash, \\\" for quote"
    elif echo "$ERROR_OUTPUT" | grep -q "Expected.*string key"; then
        FIX="Object keys must be quoted strings in JSON"
    fi

    jq -n \
        --arg rule "json-valid" \
        --arg file "$FILE" \
        --argjson line "$LINE" \
        --arg message "$MESSAGE" \
        --arg fix "$FIX" \
        '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
    exit 1
fi

# Valid JSON
exit 0
