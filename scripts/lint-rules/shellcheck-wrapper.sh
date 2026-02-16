#!/bin/bash
set -euo pipefail

# shellcheck-wrapper.sh — Run shellcheck with agent-friendly output
# Reformats shellcheck errors with fix instructions

FILE="$1"

# Only run on shell scripts
if [[ ! "$FILE" =~ \.sh$ ]]; then
    [[ -r "$FILE" ]] || exit 0
    first_line="$(head -1 "$FILE")" || exit 0
    if ! grep -qE '^#!.*/(bash|sh)' <<< "$first_line"; then
        exit 0
    fi
fi

# Check if shellcheck is available
if ! command -v shellcheck >/dev/null 2>&1; then
    # Shellcheck not installed - skip silently
    exit 0
fi

# Run shellcheck with JSON output
shellcheck_rc=0
if ! SHELLCHECK_OUTPUT="$(shellcheck -f json "$FILE" 2>&1)"; then
    shellcheck_rc=$?
fi

# Exit on shellcheck execution failures (syntax/config issues still return JSON array).
if (( shellcheck_rc != 0 )) && ! jq -e 'type == "array"' <<< "$SHELLCHECK_OUTPUT" >/dev/null; then
    exit 0
fi

# If no issues, exit success
if [[ -z "$SHELLCHECK_OUTPUT" ]] || [[ "$SHELLCHECK_OUTPUT" == "[]" ]]; then
    exit 0
fi

# Parse first error and reformat with fix instructions
FIRST_ERROR=$(echo "$SHELLCHECK_OUTPUT" | jq -r '.[0] // empty')

if [[ -z "$FIRST_ERROR" ]]; then
    exit 0
fi

# Extract fields
CODE=$(echo "$FIRST_ERROR" | jq -r '.code')
LINE=$(echo "$FIRST_ERROR" | jq -r '.line')
MESSAGE=$(echo "$FIRST_ERROR" | jq -r '.message')

# Generate fix instruction based on common codes
FIX="Check shellcheck wiki: https://www.shellcheck.net/wiki/SC${CODE}"
case "$CODE" in
    2086)
        FIX="Quote variables to prevent word splitting: \"\$VAR\" instead of \$VAR"
        ;;
    2155)
        FIX="Separate declaration and assignment: declare VAR; VAR=\$(command)"
        ;;
    2034)
        FIX="Remove unused variable or prefix with _ to indicate intentional: _VAR=..."
        ;;
    2164)
        FIX="Use 'cd ... || exit' to handle directory change failures"
        ;;
esac

# Output JSON
jq -n \
    --arg rule "shellcheck" \
    --arg file "$FILE" \
    --argjson line "$LINE" \
    --arg message "SC${CODE}: ${MESSAGE}" \
    --arg fix "$FIX" \
    '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'

exit 1
