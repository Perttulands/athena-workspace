#!/bin/bash
set -euo pipefail

# dependency-direction.sh - Enforce layer dependency direction
# Lower layers should not import/source higher layers

FILE="$1"

# Skip if not a shell script or JS file
if [[ ! "$FILE" =~ \.(sh|js)$ ]]; then
    exit 0
fi

# Define layer boundaries (from SWARM-IMPLEMENTATION.md)
# Layer 0: tools (br, tmux, etc) - no workspace imports
# Layer 1: scripts/ - can use tools, not templates or state analysis
# Layer 2: state/ - can be read by any layer, written only by scripts
# Layer 3: templates/ - can reference docs, not scripts
# Layer 5: flywheel - can read everything

# Get file directory to determine layer
dir=$(dirname "$FILE")
filename=$(basename "$FILE")

# Detect layer
if [[ "$dir" =~ ^scripts/lint-rules ]]; then
    layer="lint-rules"
    allowed_imports="(state/|docs/)"
elif [[ "$dir" =~ ^scripts ]]; then
    layer="scripts"
    allowed_imports="(state/|docs/)"
elif [[ "$dir" =~ ^templates ]]; then
    layer="templates"
    allowed_imports="(docs/)"
else
    # Other directories - no strict enforcement yet
    exit 0
fi

# Check for source/require/import statements
violations=()

# For shell scripts: check 'source' statements
if [[ "$FILE" =~ \.sh$ ]]; then
    while IFS= read -r line_num; do
        line=$(sed -n "${line_num}p" "$FILE")

        # Skip comments
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Check for source statements
        if [[ "$line" =~ source[[:space:]]+ ]]; then
            sourced=$(echo "$line" | sed -E 's/.*source[[:space:]]+([^[:space:]]+).*/\1/' | tr -d '"' | tr -d "'")

            # Check if sourced path violates layer rules
            if [[ "$layer" == "scripts" ]] && [[ "$sourced" =~ templates/ ]]; then
                violations+=("$line_num:scripts layer cannot source templates/ (line: $line)")
            fi
            if [[ "$layer" == "templates" ]] && [[ "$sourced" =~ scripts/ ]]; then
                violations+=("$line_num:templates layer cannot source scripts/ (line: $line)")
            fi
        fi
    done < <(grep -n "source " "$FILE" | cut -d: -f1)
fi

# For JS files: check require/import statements
if [[ "$FILE" =~ \.js$ ]]; then
    while IFS= read -r line_num; do
        line=$(sed -n "${line_num}p" "$FILE")

        # Check for require/import
        if [[ "$line" =~ (require\(|import.*from) ]]; then
            imported=$(echo "$line" | sed -E 's/.*(require\(|from)[[:space:]]*['\''"]([^'\''"]+).*/\2/')

            # Check if imported path violates layer rules
            if [[ "$layer" == "scripts" ]] && [[ "$imported" =~ templates/ ]]; then
                violations+=("$line_num:scripts layer cannot import templates/ (line: $line)")
            fi
        fi
    done < <(grep -n -E "(require\(|import.*from)" "$FILE" | cut -d: -f1)
fi

# Report violations
if [[ ${#violations[@]} -gt 0 ]]; then
    first_violation="${violations[0]}"
    line_num=$(echo "$first_violation" | cut -d: -f1)
    message=$(echo "$first_violation" | cut -d: -f2-)

    jq -n \
        --arg rule "dependency-direction" \
        --arg file "$FILE" \
        --argjson line "$line_num" \
        --arg message "$message" \
        --arg fix "Move shared logic to a lower layer (state/ or docs/) or use a callback pattern to invert the dependency" \
        '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
    exit 1
fi

exit 0
