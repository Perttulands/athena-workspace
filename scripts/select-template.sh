#!/usr/bin/env bash
# Select best template for a task based on description and historical scores
set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
TEMPLATES_DIR="$WORKSPACE_ROOT/templates"
SCORES_FILE="$WORKSPACE_ROOT/state/template-scores.json"

show_help() {
    cat << 'EOF'
Usage: select-template.sh [OPTIONS] <task-description>

Automatically selects the best prompt template for a task based on:
- Keyword matching from task description
- Historical success rates from template-scores.json

OPTIONS:
    --json              Output in JSON format
    --help              Show this help message

EXAMPLES:
    select-template.sh "Fix the auth timeout bug"
    select-template.sh --json "Add user profile page"
    select-template.sh "Refactor database layer"

EXIT CODES:
    0 - Success
    1 - Error

OUTPUT (human-readable):
    Recommended template: bug-fix
    Template path: templates/bug-fix.md
    Success rate: 83% (12 uses)
    Reason: Task keywords match bug/fix pattern

OUTPUT (--json):
    {
      "template": "bug-fix",
      "path": "templates/bug-fix.md",
      "success_rate": 0.83,
      "uses": 12,
      "reason": "Task keywords match bug/fix pattern",
      "confidence": "high"
    }
EOF
}

# Parse arguments
OUTPUT_JSON=false
TASK_DESC=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            TASK_DESC="$1"
            shift
            ;;
    esac
done

if [[ -z "$TASK_DESC" ]]; then
    echo "Error: task description required" >&2
    show_help >&2
    exit 1
fi

# Classify task type by keyword matching
classify_task() {
    local desc="$1"
    local lower_desc
    lower_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')

    # Bug/fix keywords
    if echo "$lower_desc" | grep -qE '\b(fix|bug|debug|broken|error|issue|crash|timeout)\b'; then
        echo "bug-fix"
        return
    fi

    # Feature keywords
    if echo "$lower_desc" | grep -qE '\b(add|implement|create|new|feature|build|enable)\b'; then
        echo "feature"
        return
    fi

    # Refactor keywords
    if echo "$lower_desc" | grep -qE '\b(refactor|clean|improve|optimize|restructure|reorganize)\b'; then
        echo "refactor"
        return
    fi

    # Doc keywords
    if echo "$lower_desc" | grep -qE '\b(doc|document|write|readme|guide|explain)\b'; then
        echo "docs"
        return
    fi

    # Script keywords
    if echo "$lower_desc" | grep -qE '\b(script|build|deploy|automate|pipeline)\b'; then
        echo "script"
        return
    fi

    # Default to custom
    echo "custom"
}

# Get template scores from state/template-scores.json
get_template_score() {
    local template_name="$1"

    if [[ ! -f "$SCORES_FILE" ]]; then
        echo "null"
        return
    fi

    local score
    if ! score="$(jq -r --arg tpl "$template_name" '.templates[$tpl] // null' "$SCORES_FILE")"; then
        echo "Warning: failed to parse template scores from $SCORES_FILE" >&2
        score="null"
    fi
    echo "$score"
}

# Main selection logic
selected_template=$(classify_task "$TASK_DESC")
template_path="$TEMPLATES_DIR/${selected_template}.md"

# Check if template file exists
if [[ ! -f "$template_path" ]]; then
    echo "Error: template file not found: $template_path" >&2
    exit 1
fi

# Get historical scores
score_data=$(get_template_score "$selected_template")

if [[ "$score_data" == "null" ]]; then
    # No historical data
    success_rate="null"
    uses=0
    confidence="low"
    reason="Task keywords match $selected_template pattern (no historical data yet)"
else
    success_rate=$(echo "$score_data" | jq -r '.success_rate')
    uses=$(echo "$score_data" | jq -r '.uses')

    # Determine confidence based on success rate and sample size
    if (( uses >= 5 )); then
        if awk "BEGIN {exit !($success_rate > 0.7)}"; then
            confidence="high"
            reason="Task keywords match $selected_template pattern. Historical success rate: ${success_rate} (${uses} uses)"
        elif awk "BEGIN {exit !($success_rate > 0.5)}"; then
            confidence="medium"
            reason="Task keywords match $selected_template pattern. Historical success rate: ${success_rate} (${uses} uses) - moderate performance"
        else
            confidence="low"
            reason="WARNING: Task keywords match $selected_template pattern, but historical success rate is low: ${success_rate} (${uses} uses). Consider using a different template."
        fi
    else
        confidence="low"
        reason="Task keywords match $selected_template pattern. Limited historical data (${uses} uses)"
    fi
fi

# Output results
if [[ "$OUTPUT_JSON" == "true" ]]; then
    jq -n \
        --arg template "$selected_template" \
        --arg path "$template_path" \
        --argjson success_rate "${success_rate:-null}" \
        --argjson uses "${uses:-0}" \
        --arg reason "$reason" \
        --arg confidence "$confidence" \
        '{
            template: $template,
            path: $path,
            success_rate: $success_rate,
            uses: $uses,
            reason: $reason,
            confidence: $confidence
        }'
else
    echo "Recommended template: $selected_template"
    echo "Template path: $template_path"
    if [[ "$success_rate" != "null" ]]; then
        echo "Success rate: $(awk "BEGIN {printf \"%.0f%%\", $success_rate * 100}") ($uses uses)"
    else
        echo "Success rate: No data yet"
    fi
    echo "Confidence: $confidence"
    echo "Reason: $reason"
fi

exit 0
