#!/bin/bash
# ralph.sh - Execute PRD using bash loop (fresh session per iteration)
# Usage: ./ralph.sh <project-name> <max-iterations> <sleep-seconds> <model>
# Model is REQUIRED — no silent defaults.
# Example: ./ralph.sh finance_calc 20 2 opus
#
# Use for PRDs with >20 tasks (fresh session avoids context bloat)
# For <20 tasks, use ralph-native.sh (native Tasks, single session)

set -euo pipefail
set -E

# Trap errors and log them instead of dying silently
trap 'echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: ralph.sh died at line $LINENO (exit code $?). Command: $BASH_COMMAND" | tee -a ralph-error.log >&2' ERR

PROJECT="${1:?Usage: ralph.sh <project-name> [max-iterations] [sleep-seconds] [model]}"
MAX=${2:-10}
SLEEP=${3:-2}
MODEL="${4:-}"
if [[ -z "$MODEL" ]]; then
    echo "Error: model is REQUIRED. No silent defaults." >&2
    echo "  Usage: ralph.sh <project-name> [max-iterations] [sleep-seconds] <model>" >&2
    echo "  Valid models: sonnet, opus, haiku, codex, codex-medium" >&2
    exit 1
fi

# Validate MODEL at startup
case "$MODEL" in
    sonnet|opus|haiku|codex|codex-medium) ;;
    *)
        echo "Error: unknown model '$MODEL'" >&2
        echo "  Valid models: sonnet, opus, haiku, codex, codex-medium" >&2
        exit 1
        ;;
esac

DEBUG_LOG="ralph-debug.log"

# Run prompt through the configured model
# Supports: sonnet, opus, haiku (claude), codex, codex-medium (codex CLI)
run_model() {
    local prompt="$1"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] run_model START model=$MODEL" >> "$DEBUG_LOG"
    case "$MODEL" in
        codex)
            codex exec --yolo "$prompt" 2>>ralph-error.log
            ;;
        codex-medium)
            codex exec --yolo -c 'model_reasoning_effort="medium"' "$prompt" 2>>ralph-error.log
            ;;
        *)
            claude --model "$MODEL" --dangerously-skip-permissions -p "$prompt" 2>>ralph-error.log
            ;;
    esac
}

PROJECT_UPPER=$(echo "$PROJECT" | tr '[:lower:]' '[:upper:]')
PRD_FILE="PRD_${PROJECT_UPPER}.md"
PROGRESS_FILE="progress_${PROJECT}.txt"

# Get sprint number for a given task ID (e.g., US-001 -> 1, US-REVIEW-S2 -> 2)
get_sprint_for_task() {
    local task_id="$1"
    local prd_file="$2"

    # Extract sprint number from review tasks (US-REVIEW-S1 -> 1)
    if [[ "$task_id" =~ US-REVIEW-S([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # For regular tasks, find which sprint section contains the task
    # Read PRD and track current sprint number
    local current_sprint=0
    while IFS= read -r line; do
        # Detect sprint header: ## Sprint N:
        if [[ "$line" =~ ^##[[:space:]]+Sprint[[:space:]]+([0-9]+): ]]; then
            current_sprint="${BASH_REMATCH[1]}"
        fi
        # Found the task in current sprint
        if [[ "$line" =~ \*\*${task_id}\*\* ]]; then
            echo "$current_sprint"
            return
        fi
    done < "$prd_file"

    echo "0"  # Not found
}

# Check if this is the first task in a sprint (first [ ] task after sprint header)
is_first_task_in_sprint() {
    local task_id="$1"
    local sprint_num="$2"
    local prd_file="$3"

    local in_sprint=0
    while IFS= read -r line; do
        # Detect target sprint header
        if [[ "$line" =~ ^##[[:space:]]+Sprint[[:space:]]+${sprint_num}: ]]; then
            in_sprint=1
            continue
        fi
        # Detect next sprint header (exit)
        if [[ $in_sprint -eq 1 && "$line" =~ ^##[[:space:]]+Sprint[[:space:]]+[0-9]+: ]]; then
            break
        fi
        # In target sprint, find first incomplete task
        if [[ $in_sprint -eq 1 && "$line" =~ ^-[[:space:]]\[[[:space:]]\][[:space:]]\*\*([A-Z0-9-]+)\*\* ]]; then
            local found_task="${BASH_REMATCH[1]}"
            if [[ "$found_task" == "$task_id" ]]; then
                echo "1"
            else
                echo "0"
            fi
            return
        fi
    done < "$prd_file"

    echo "0"
}

# Check if all tasks in a sprint are complete
is_sprint_complete() {
    local sprint_num="$1"
    local prd_file="$2"

    local in_sprint=0
    while IFS= read -r line; do
        # Detect target sprint header
        if [[ "$line" =~ ^##[[:space:]]+Sprint[[:space:]]+${sprint_num}: ]]; then
            in_sprint=1
            continue
        fi
        # Detect next sprint header (exit)
        if [[ $in_sprint -eq 1 && "$line" =~ ^##[[:space:]]+Sprint[[:space:]]+[0-9]+: ]]; then
            break
        fi
        # In target sprint, check for any incomplete task
        if [[ $in_sprint -eq 1 && "$line" =~ ^-[[:space:]]\[[[:space:]]\] ]]; then
            echo "0"
            return
        fi
    done < "$prd_file"

    echo "1"
}

# Update sprint status in PRD file
update_sprint_status() {
    local sprint_num="$1"
    local new_status="$2"
    local prd_file="$3"

    # Use sed to update the Status line for the specific sprint
    # Pattern: Find "## Sprint N:" then update the next "**Status:**" line
    sed -i.bak -E "/^## Sprint ${sprint_num}:/,/^## Sprint [0-9]+:|^---$/{
        s/(\*\*Status:\*\*) (NOT STARTED|IN PROGRESS|COMPLETE)/\1 ${new_status}/
    }" "$prd_file" && rm -f "${prd_file}.bak"
}

# Validate PRD exists
if [[ ! -f "$PRD_FILE" ]]; then
    echo "Error: $PRD_FILE not found"
    exit 1
fi

# Initialize progress file if empty/missing
if [[ ! -s "$PROGRESS_FILE" ]]; then
    cat > "$PROGRESS_FILE" << 'EOF'
# Progress Log

## Learnings
(Patterns discovered during implementation)

---
EOF
fi

echo "==========================================="
echo "  Ralph - Bash Loop Mode"
echo "  Project: $PROJECT"
echo "  PRD: $PRD_FILE"
echo "  Progress: $PROGRESS_FILE"
echo "  Max iterations: $MAX"
echo "  Model: $MODEL"
echo "==========================================="
echo ""

for ((i=1; i<=MAX; i++)); do
    echo "==========================================="
    echo "  Iteration $i of $MAX"
    echo "==========================================="

    # Pre-iteration: Detect current task and update sprint status to IN PROGRESS if needed
    if current_task="$(grep -m1 "^- \[ \] \*\*US-" "$PRD_FILE" | sed -E 's/.*\*\*([A-Z0-9-]+)\*\*.*/\1/')"; then
        :
    else
        current_task=""
    fi
    ITER_START_EPOCH=$(date -u +%s)
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] iteration=$i START model=$MODEL task=${current_task:-none}" >> "$DEBUG_LOG"
    if [[ -n "$current_task" ]]; then
        sprint_num=$(get_sprint_for_task "$current_task" "$PRD_FILE")
        if [[ "$sprint_num" != "0" ]]; then
            is_first=$(is_first_task_in_sprint "$current_task" "$sprint_num" "$PRD_FILE")
            if [[ "$is_first" == "1" ]]; then
                # Check if sprint status is NOT STARTED
                if grep -A5 "^## Sprint ${sprint_num}:" "$PRD_FILE" | grep -q "\*\*Status:\*\* NOT STARTED"; then
                    echo "  >> Sprint $sprint_num: NOT STARTED -> IN PROGRESS"
                    update_sprint_status "$sprint_num" "IN PROGRESS" "$PRD_FILE"
                fi
            fi
        fi
    fi

    result=$(run_model "You are Ralph, an autonomous coding agent. Do exactly ONE task per iteration.

Do NOT use EnterPlanMode. Implement directly using TDD (RED-GREEN-VERIFY).

## Task Detection

Read $PRD_FILE, find first incomplete task (marked [ ]).
- If task ID contains 'REVIEW': follow Review Process below.
- Otherwise: follow Regular Process.

Read $PROGRESS_FILE Learnings section for patterns from previous iterations.

## Regular Process

1. Implement the ONE task using TDD.
2. Run tests. If tests PASS:
   - Mark \`- [ ]\` → \`- [x]\`, commit: \`feat: [task description]\`
   - Verify files exist: \`ls -la <impl_file>\` and \`ls -la <test_file>\` (size > 0)
   - Append progress to BOTTOM of $PROGRESS_FILE (after --- separator) AND output to console
3. If tests FAIL: do NOT mark [x], do NOT commit. Append failure notes to $PROGRESS_FILE.

### Progress Format (append to $PROGRESS_FILE AND output to console):
\`\`\`
## Iteration [N] - [Task Name]
- What was implemented, files changed
- Learnings for future iterations
**Summary:** Task: [US-XXX] | Files: [...] | Tests: [PASS/FAIL] | Review: [PASSED/ISSUES/SKIPPED] | Next: [next task or COMPLETE]
---
\`\`\`

### Post-Task Review

Review your code against linus-prompt-code-review.md (good taste, no special cases, simplicity, no duplication).
- Issues found: insert fix tasks as \`- [ ] **US-XXXa** Fix desc (5 min)\` after completed task, output \`<review-issues-found/>\`
- No issues: output progress notes then \`<review-passed/>\`

## Review Process (REVIEW in task ID)

1. Read review task acceptance criteria for scope (which US-XXX tasks to review)
2. Run \`git log\` for those tasks, read ALL code files together
3. Apply Linus criteria + cross-task analysis (duplication between tasks, consistent naming, data flow, integration)
4. Issues found: insert fix tasks before the review task, append findings to $PROGRESS_FILE, output \`<review-issues-found/>\`. Do NOT mark review [x].
5. No issues: append review notes to $PROGRESS_FILE, verify with \`tail -20 $PROGRESS_FILE\`, mark [x], commit \`docs: [review task] complete\`, output \`<review-passed/>\`

## AGENTS.md

If you discover a reusable pattern, add it to AGENTS.md in the project root.

## End Condition

Before outputting \`<promise>COMPLETE</promise>\`: read $PRD_FILE top to bottom. Only output COMPLETE if EVERY task is [x]. If any [ ] remains, just end.")

    echo "$result"
    echo ""

    ITER_END_EPOCH=$(date -u +%s)
    ITER_DURATION=$((ITER_END_EPOCH - ITER_START_EPOCH))
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] iteration=$i END model=$MODEL task=${current_task:-none} duration=${ITER_DURATION}s" >> "$DEBUG_LOG"

    # Post-iteration: Check if sprint is now complete and update status
    if [[ -n "$current_task" && "$sprint_num" != "0" ]]; then
        sprint_complete=$(is_sprint_complete "$sprint_num" "$PRD_FILE")
        if [[ "$sprint_complete" == "1" ]]; then
            # Check if sprint status is IN PROGRESS (not already COMPLETE)
            if grep -A5 "^## Sprint ${sprint_num}:" "$PRD_FILE" | grep -q "\*\*Status:\*\* IN PROGRESS"; then
                echo "  >> Sprint $sprint_num: IN PROGRESS -> COMPLETE"
                update_sprint_status "$sprint_num" "COMPLETE" "$PRD_FILE"
            fi
        fi
    fi

    if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
        # Validate: count incomplete task headers with grep
        # Note: Manual tasks (US-MANUAL-*) don't have [ ] so are naturally excluded
        if incomplete="$(grep -c "^- \[ \] \*\*US-" "$PRD_FILE")"; then
            :
        else
            incomplete=0
        fi
        incomplete=${incomplete:-0}

        if [[ "$incomplete" -gt 0 ]]; then
            echo ""
            echo "==========================================="
            echo "  WARNING: COMPLETE signal rejected"
            echo "  Found $incomplete incomplete task header(s)"
            echo "  Continuing to next iteration..."
            echo "==========================================="
            sleep "$SLEEP"
            continue
        fi

        echo "==========================================="
        echo "  All tasks complete after $i iterations!"
        echo "==========================================="
        exit 0
    fi

    sleep "$SLEEP"
done

echo "==========================================="
echo "  Reached max iterations ($MAX)"
echo "==========================================="
exit 1
