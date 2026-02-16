#!/bin/bash
set -euo pipefail

# no-hardcoded-paths.sh — Detect hardcoded absolute paths
# Outputs JSON with fix instructions on failure

FILE="$1"

# Skip non-text files (binary files)
if [[ ! -r "$FILE" ]]; then
    # Unreadable files are skipped by this content-based rule.
    exit 0
fi
if [[ -f "$FILE" ]] && grep -qI . "$FILE"; then
    : # Text file, continue
else
    # Binary or unreadable - skip
    exit 0
fi

# Look for hardcoded paths like /home/
LINE_NUM=0
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))

    # Check for /home/ specifically
    if echo "$line" | grep -qE '"/home/[^"]*"'; then
        # Found hardcoded path
        jq -n \
            --arg rule "no-hardcoded-paths" \
            --arg file "$FILE" \
            --argjson line "$LINE_NUM" \
            --arg message "Hardcoded absolute path /home/ found" \
            --arg fix "Use \$HOME or relative paths instead of hardcoded /home/" \
            '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
        exit 1
    fi

    # Check for other common hardcoded paths
    if echo "$line" | grep -qE '"/usr/local/[^"]*"|"/opt/[^"]*"' | grep -v "/usr/local/bin" | grep -v "/opt/homebrew"; then
        jq -n \
            --arg rule "no-hardcoded-paths" \
            --arg file "$FILE" \
            --argjson line "$LINE_NUM" \
            --arg message "Hardcoded absolute path found" \
            --arg fix "Use environment variables or relative paths instead of hardcoded absolute paths" \
            '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
        exit 1
    fi
done < "$FILE"

# All good
exit 0
