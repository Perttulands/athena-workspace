#!/bin/bash
set -euo pipefail

# lint-agent.sh — Agent-friendly linter framework
# Runs modular lint rules and outputs structured errors with fix instructions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$SCRIPT_DIR/lint-rules"

show_help() {
    cat <<EOF
Usage: lint-agent.sh [OPTIONS] <file-or-directory>

Agent-friendly linter framework with actionable fix instructions.

OPTIONS:
    --help          Show this help message
    --json          Output JSON format (default: human-readable)
    --rule <name>   Run only the specified rule

EXAMPLES:
    lint-agent.sh src/                    # Lint all files in src/
    lint-agent.sh --json myfile.sh        # JSON output for agent consumption
    lint-agent.sh --rule json-valid *.json  # Run specific rule
EOF
}

# Parse arguments
JSON_OUTPUT=false
SPECIFIC_RULE=""
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --rule)
            SPECIFIC_RULE="$2"
            shift 2
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "Error: No file or directory specified" >&2
    show_help
    exit 1
fi

if [[ ! -e "$TARGET" ]]; then
    echo "Error: Target does not exist: $TARGET" >&2
    exit 1
fi

# Collect all files to lint
FILES=()
if [[ -d "$TARGET" ]]; then
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$TARGET" -type f -print0)
elif [[ -f "$TARGET" ]]; then
    FILES=("$TARGET")
fi

# Run rules and collect results
ALL_RESULTS=()
EXIT_CODE=0

for file in "${FILES[@]}"; do
    # Determine which rules apply based on file extension
    EXT="${file##*.}"

    # Get applicable rules
    RULES=()
    if [[ -n "$SPECIFIC_RULE" ]]; then
        if [[ -x "$RULES_DIR/${SPECIFIC_RULE}.sh" ]]; then
            RULES=("$RULES_DIR/${SPECIFIC_RULE}.sh")
        fi
    else
        # All executable rules
        while IFS= read -r rule; do
            RULES+=("$rule")
        done < <(find "$RULES_DIR" -name "*.sh" -type f -executable)
    fi

    # Run each applicable rule
    for rule in "${RULES[@]}"; do
        RULE_NAME=$(basename "$rule" .sh)

        # Run the rule - it outputs JSON on failure, nothing on pass
        if ! RULE_OUTPUT=$("$rule" "$file" 2>&1); then
            EXIT_CODE=1
            # Rule failed - parse its output
            if echo "$RULE_OUTPUT" | jq -e . >/dev/null 2>&1; then
                # Valid JSON from rule
                ALL_RESULTS+=("$RULE_OUTPUT")
            else
                # Rule didn't output JSON - wrap it
                WRAPPED=$(jq -n \
                    --arg rule "$RULE_NAME" \
                    --arg file "$file" \
                    --arg msg "$RULE_OUTPUT" \
                    '{rule: $rule, file: $file, line: 0, message: $msg, fix: "Check rule output for details"}')
                ALL_RESULTS+=("$WRAPPED")
            fi
        fi
    done
done

# Output results
if [[ ${#ALL_RESULTS[@]} -eq 0 ]]; then
    # All checks passed
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "[]"
    fi
    exit 0
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Combine all results into JSON array
    printf '%s\n' "${ALL_RESULTS[@]}" | jq -s .
else
    # Human-readable output
    echo "Lint issues found:"
    echo ""
    for result in "${ALL_RESULTS[@]}"; do
        RULE=$(echo "$result" | jq -r '.rule')
        FILE=$(echo "$result" | jq -r '.file')
        LINE=$(echo "$result" | jq -r '.line')
        MSG=$(echo "$result" | jq -r '.message')
        FIX=$(echo "$result" | jq -r '.fix')

        echo "[$RULE] $FILE:$LINE"
        echo "  Issue: $MSG"
        echo "  Fix: $FIX"
        echo ""
    done
fi

exit $EXIT_CODE
