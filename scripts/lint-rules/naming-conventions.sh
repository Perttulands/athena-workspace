#!/bin/bash
set -euo pipefail

# naming-conventions.sh - Enforce kebab-case naming conventions

FILE="$1"

filename=$(basename "$FILE")
dir=$(dirname "$FILE")

# Define naming rules based on directory and extension
expected_pattern=""
suggested_name=""

# Scripts: kebab-case with .sh extension
if [[ "$dir" =~ scripts ]] && [[ "$FILE" =~ \.sh$ ]]; then
    if [[ ! "$filename" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.sh$ ]]; then
        expected_pattern="kebab-case (lowercase letters, numbers, hyphens only)"
        suggested_name=$(echo "$filename" | sed -E 's/([A-Z])/-\L\1/g' | sed 's/^-//' | tr '_' '-')
    fi
fi

# Docs: kebab-case with .md extension
if [[ "$dir" =~ docs ]] && [[ "$FILE" =~ \.md$ ]]; then
    if [[ ! "$filename" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]] && [[ "$filename" != "INDEX.md" ]] && [[ "$filename" != "README.md" ]]; then
        expected_pattern="kebab-case (lowercase letters, numbers, hyphens only)"
        suggested_name=$(echo "$filename" | sed -E 's/([A-Z])/-\L\1/g' | sed 's/^-//' | tr '_' '-')
    fi
fi

# Templates: kebab-case with .md extension
if [[ "$dir" =~ templates ]] && [[ "$FILE" =~ \.md$ ]]; then
    if [[ ! "$filename" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]] && [[ "$filename" != "README.md" ]]; then
        expected_pattern="kebab-case (lowercase letters, numbers, hyphens only)"
        suggested_name=$(echo "$filename" | sed -E 's/([A-Z])/-\L\1/g' | sed 's/^-//' | tr '_' '-')
    fi
fi

# State files: <bead-id>.json pattern (bd-XXXX.json)
if [[ "$dir" =~ state/(runs|results) ]] && [[ "$FILE" =~ \.json$ ]]; then
    if [[ ! "$filename" =~ ^bd-[a-z0-9]+\.json$ ]]; then
        expected_pattern="bead ID format: bd-XXXX.json"
        suggested_name="bd-$(echo "$filename" | sed 's/\.json$//' | tr 'A-Z' 'a-z').json"
    fi
fi

# Report violation if any
if [[ -n "$expected_pattern" ]]; then
    jq -n \
        --arg rule "naming-conventions" \
        --arg file "$FILE" \
        --argjson line 0 \
        --arg message "File name '$filename' doesn't match naming convention: $expected_pattern" \
        --arg fix "Rename file to match convention: $suggested_name" \
        '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
    exit 1
fi

exit 0
