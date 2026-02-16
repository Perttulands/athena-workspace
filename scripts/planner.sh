#!/usr/bin/env bash
set -euo pipefail

# planner.sh — Decomposes goals into sequenced task plans
# Usage:
#   planner.sh create <goal-description> [--repo <path>]
#   planner.sh show <plan-id>
#   planner.sh list
#   planner.sh validate <plan-id>

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
PLANS_DIR="$WORKSPACE_ROOT/state/plans"
TEMPLATE_SCORES="$WORKSPACE_ROOT/state/template-scores.json"
PLAN_SCHEMA="$WORKSPACE_ROOT/state/schemas/plan.schema.json"
SELECT_TEMPLATE="$WORKSPACE_ROOT/scripts/select-template.sh"

mkdir -p "$PLANS_DIR"

usage() {
    cat <<EOF
Usage: planner.sh <command> [options]

Commands:
  create <goal> [--repo <path>]  Generate a plan from a goal description
  show <plan-id>                 Display a plan
  list                           List all plans with status
  validate <plan-id>             Check plan dependencies are satisfiable

Options:
  --repo <path>                  Repository path (for context, not used yet)
  --help                         Show this help message

Examples:
  planner.sh create "Add user authentication with JWT"
  planner.sh list
  planner.sh validate plan-abc123
  planner.sh show plan-abc123
EOF
}

# Generate unique plan ID
generate_plan_id() {
    echo "plan-$(date +%s)-$$"
}

# Parse goal into task breakdown
# Returns task objects as JSON array
parse_goal_into_tasks() {
    local goal="$1"
    local task_num=1
    local tasks=()

    # Keyword-based task extraction
    # Look for keywords that indicate discrete tasks
    local task_patterns=(
        "fix.*bug|bug.*fix"
        "add|create|implement|build"
        "refactor|clean|reorganize"
        "test|validate|verify"
        "document|doc|write.*doc"
        "deploy|release|ship"
        "migrate|upgrade|update"
        "optimize|improve|enhance"
    )

    # Split on "and" to identify multiple tasks
    local goal_lower
    goal_lower=$(echo "$goal" | tr '[:upper:]' '[:lower:]')

    # Simple heuristic: split on " and ", " then ", " after "
    local subtasks
    subtasks=$(echo "$goal_lower" | sed -E 's/ and | then | after /\n/g')

    # For each subtask, classify and create task object
    while IFS= read -r subtask; do
        [[ -z "$subtask" ]] && continue

        # Classify task type
        local template="custom"
        if echo "$subtask" | grep -qE '\b(fix|bug)\b'; then
            template="bug-fix"
        elif echo "$subtask" | grep -qE '\b(add|create|implement|build|feature)\b'; then
            template="feature"
        elif echo "$subtask" | grep -qE '\b(refactor|clean|reorganize)\b'; then
            template="refactor"
        elif echo "$subtask" | grep -qE '\b(test|validate|verify)\b'; then
            template="test"
        elif echo "$subtask" | grep -qE '\b(document|doc|write)\b'; then
            template="docs"
        elif echo "$subtask" | grep -qE '\b(deploy|release|ship)\b'; then
            template="deploy"
        fi

        # Get estimated duration from template scores
        local duration="null"
        if [[ -f "$TEMPLATE_SCORES" ]]; then
            if ! duration="$(jq -r ".templates[\"$template\"].avg_duration_s // null" "$TEMPLATE_SCORES")"; then
                echo "Warning: failed to read template score for '$template', using null duration" >&2
                duration="null"
            fi
        fi

        # Create task object
        local task_id="task-$task_num"
        local title
        title=$(echo "$subtask" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
        title="${title^}"  # Capitalize first letter

        local task_json
        task_json=$(jq -n \
            --arg id "$task_id" \
            --arg title "$title" \
            --arg template "$template" \
            --argjson duration "$duration" \
            --arg desc "$subtask" \
            '{
                task_id: $id,
                title: $title,
                template: $template,
                depends_on: [],
                estimated_duration_s: $duration,
                description: $desc
            }')

        tasks+=("$task_json")
        ((task_num++))
    done <<< "$subtasks"

    # Combine tasks into JSON array
    local result="["
    local first=true
    for task in "${tasks[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="$task"
    done
    result+="]"

    echo "$result"
}

# Detect dependencies based on keywords
# Updates tasks array with depends_on fields
detect_dependencies() {
    local tasks_json="$1"

    # For now, simple sequential dependency: task-2 depends on task-1, task-3 on task-2, etc.
    # TODO: Parse "after X" patterns for explicit dependencies

    local updated_tasks
    updated_tasks=$(echo "$tasks_json" | jq '
        [
            .[] |
            .task_id as $id |
            ($id | sub("task-"; "") | tonumber) as $num |
            if $num > 1 then
                .depends_on = ["task-" + ($num - 1 | tostring)]
            else
                .depends_on = []
            end
        ]
    ')

    echo "$updated_tasks"
}

# Compute parallelizable groups (topological sort)
compute_parallel_groups() {
    local tasks_json="$1"

    # Simple algorithm: group tasks by max dependency depth
    local groups
    groups=$(echo "$tasks_json" | jq -c '
        def max_depth($tasks):
            if (.depends_on | length) == 0 then 0
            else
                [.depends_on[] | $tasks | map(select(.task_id == .)) | .[0] | max_depth($tasks)] | max + 1
            end;

        . as $tasks |
        group_by(max_depth($tasks)) |
        map([.[] | .task_id])
    ')

    echo "$groups"
}

# Create a new plan
cmd_create() {
    local goal=""
    local repo_path=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --repo)
                repo_path="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$goal" ]]; then
                    goal="$1"
                else
                    goal="$goal $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$goal" ]]; then
        echo "Error: goal description required" >&2
        usage
        exit 1
    fi

    local plan_id
    plan_id=$(generate_plan_id)

    # Parse goal into tasks
    local tasks_json
    tasks_json=$(parse_goal_into_tasks "$goal")

    # Detect dependencies
    tasks_json=$(detect_dependencies "$tasks_json")

    # Compute parallel groups
    local parallel_groups
    parallel_groups=$(compute_parallel_groups "$tasks_json")

    # Calculate total estimated duration
    local total_duration
    total_duration=$(echo "$tasks_json" | jq '[.[].estimated_duration_s // 0] | add')

    # Build plan JSON
    local plan_json
    plan_json=$(jq -n \
        --arg plan_id "$plan_id" \
        --arg goal "$goal" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson tasks "$tasks_json" \
        --argjson total_duration "$total_duration" \
        --argjson parallel_groups "$parallel_groups" \
        '{
            schema_version: 1,
            plan_id: $plan_id,
            goal: $goal,
            created_at: $created_at,
            status: "draft",
            tasks: $tasks,
            total_estimated_s: $total_duration,
            parallelizable_groups: $parallel_groups
        }')

    # Write plan to file (atomic)
    local plan_file="$PLANS_DIR/${plan_id}.json"
    local tmp_file="${plan_file}.tmp.$$"
    echo "$plan_json" > "$tmp_file"
    mv "$tmp_file" "$plan_file"

    echo "Created plan: $plan_id"
    echo "$plan_json" | jq -r '.tasks[] | "  - \(.task_id): \(.title) (\(.template))"'
    echo "Total estimated: $(echo "$total_duration" | awk '{print int($1/60)}') minutes"
    echo "Plan file: $plan_file"
}

# Show a plan
cmd_show() {
    local plan_id="$1"

    if [[ -z "$plan_id" ]]; then
        echo "Error: plan-id required" >&2
        usage
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [[ ! -f "$plan_file" ]]; then
        echo "Error: plan $plan_id not found" >&2
        exit 1
    fi

    jq -r '
        "Plan: \(.plan_id)",
        "Goal: \(.goal)",
        "Status: \(.status)",
        "Created: \(.created_at)",
        "Estimated duration: \(.total_estimated_s // 0 | . / 60 | floor) minutes",
        "",
        "Tasks:",
        (.tasks[] | "  \(.task_id): \(.title)\n    Template: \(.template)\n    Depends on: \(.depends_on | if length > 0 then join(", ") else "none" end)\n    Estimated: \(.estimated_duration_s // 0 | . / 60 | floor) min"),
        "",
        "Parallelization groups:",
        (.parallelizable_groups | to_entries[] | "  Level \(.key): \(.value | join(", "))")
    ' "$plan_file"
}

# List all plans
cmd_list() {
    if [[ ! -d "$PLANS_DIR" ]]; then
        echo "No plans found"
        return 0
    fi
    shopt -s nullglob
    local plan_files=("$PLANS_DIR"/plan-*.json)
    shopt -u nullglob
    if [[ ${#plan_files[@]} -eq 0 ]]; then
        echo "No plans found"
        return 0
    fi

    echo "Plans:"
    for plan_file in "${plan_files[@]}"; do
        [[ -f "$plan_file" ]] || continue
        jq -r '"  \(.plan_id) [\(.status)] - \(.goal) (\(.tasks | length) tasks)"' "$plan_file"
    done
}

# Validate a plan
cmd_validate() {
    local plan_id="$1"

    if [[ -z "$plan_id" ]]; then
        echo "Error: plan-id required" >&2
        usage
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [[ ! -f "$plan_file" ]]; then
        echo "Error: plan $plan_id not found" >&2
        exit 1
    fi

    local errors=0

    # Check 1: All task IDs are unique
    local duplicates
    duplicates=$(jq -r '[.tasks[].task_id] | group_by(.) | map(select(length > 1)) | .[] | .[0]' "$plan_file")
    if [[ -n "$duplicates" ]]; then
        echo "Error: duplicate task IDs: $duplicates" >&2
        ((errors++))
    fi

    # Check 2: All depends_on references exist
    local invalid_deps
    invalid_deps=$(jq -r '
        .tasks |
        [.[].task_id] as $all_ids |
        [.[].depends_on[]?] as $all_deps |
        ($all_deps - $all_ids) |
        unique |
        .[]
    ' "$plan_file")
    if [[ -n "$invalid_deps" ]]; then
        echo "Error: invalid dependency references: $invalid_deps" >&2
        ((errors++))
    fi

    # Check 3: No circular dependencies (simple check: no task depends on itself transitively)
    # This is a simplified check - full cycle detection requires graph algorithm
    local self_deps
    self_deps=$(jq -r '.tasks[] | select(.task_id as $id | .depends_on[] | . == $id) | .task_id' "$plan_file")
    if [[ -n "$self_deps" ]]; then
        echo "Error: task depends on itself: $self_deps" >&2
        ((errors++))
    fi

    # Check 4: Templates exist (check if template files exist)
    local templates_dir="$WORKSPACE_ROOT/templates"
    if [[ -d "$templates_dir" ]]; then
        local missing_templates
        missing_templates=$(jq -r '.tasks[].template' "$plan_file" | sort -u | while read -r template; do
            # Skip "custom" - it's a special case
            [[ "$template" == "custom" ]] && continue
            if [[ ! -f "$templates_dir/${template}.md" ]]; then
                echo "$template"
            fi
        done)
        if [[ -n "$missing_templates" ]]; then
            echo "Warning: templates not found: $missing_templates" >&2
            # Don't increment errors - this is a warning
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        echo "Plan validation passed"
        return 0
    else
        echo "Plan validation failed with $errors errors" >&2
        return 1
    fi
}

# Main command dispatch
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    create)
        cmd_create "$@"
        ;;
    show)
        cmd_show "$@"
        ;;
    list)
        cmd_list "$@"
        ;;
    validate)
        cmd_validate "$@"
        ;;
    --help)
        usage
        exit 0
        ;;
    *)
        echo "Error: unknown command '$COMMAND'" >&2
        usage
        exit 1
        ;;
esac
