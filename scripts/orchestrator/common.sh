# shellcheck shell=bash
# Depends on: lib/common.sh (for tmux_session_exists)

source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: orchestrator.sh <command> [options]

Commands:
    run [--max-hours N] [--max-tasks N] [--repo <path>]
        Start autonomous execution loop
        --max-hours N    Maximum runtime in hours (default: $ORCH_MAX_HOURS)
        --max-tasks N    Maximum tasks to complete (default: $ORCH_MAX_TASKS)
        --repo <path>    Repository path (optional)

    dry-run [--repo <path>]
        Show what would be done without executing

    status
        Show current orchestrator state

    stop
        Graceful shutdown (finish current, don't start new)

Environment variables:
    ORCH_MAX_AGENTS    Max concurrent agents (default: 4)
    ORCH_MAX_HOURS     Max runtime in hours (default: 8)
    ORCH_MAX_TASKS     Max tasks per session (default: 20)

Examples:
    orchestrator.sh dry-run
    orchestrator.sh run --max-hours 4 --max-tasks 10
    orchestrator.sh status
    orchestrator.sh stop
EOF
}

log_event() {
    local event="$1"
    shift
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON safely using jq to handle escaping
    local json
    json=$(jq -cn --arg ts "$ts" --arg event "$event" '{ts:$ts, event:$event}')

    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}"
        local value="${1#*=}"
        json=$(printf '%s' "$json" | jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}')
        shift
    done

    echo "$json" >> "$LOG_FILE"
}

json_field_or_default() {
    local file="$1" jq_filter="$2" default_value="$3" context="$4"
    local value
    if ! value="$(jq -r "$jq_filter" "$file")"; then
        echo "Warning: failed to read $context from $file" >&2
        echo "$default_value"
        return 0
    fi
    echo "$value"
}

load_calibration_patterns() {
    local patterns
    if ! patterns="$("$WORKSPACE_ROOT/scripts/calibrate.sh" patterns --json)"; then
        echo "Warning: calibrate.sh patterns failed; using empty calibration map" >&2
        echo "{}"
        return 0
    fi
    if ! echo "$patterns" | jq -e 'type == "object"' >/dev/null; then
        echo "Warning: calibrate.sh returned invalid JSON; using empty calibration map" >&2
        echo "{}"
        return 0
    fi
    echo "$patterns"
}

count_active_agents() {
    # Count run records with status=running AND a live tmux session
    if [[ ! -d "$RUNS_DIR" ]]; then
        echo "0"
        return
    fi

    local socket="${DISPATCH_TMUX_SOCKET:-/tmp/openclaw-coding-agents.sock}"
    local count=0
    for run_file in "$RUNS_DIR"/*.json; do
        [[ -e "$run_file" ]] || continue
        local status session
        status="$(json_field_or_default "$run_file" '.status // "unknown"' "unknown" "run status")"
        if [[ "$status" == "running" ]]; then
            session="$(json_field_or_default "$run_file" '.session_name // ""' "" "session name")"
            if [[ -n "$session" ]] && tmux_session_exists "$socket" "$session"; then
                count=$((count + 1))
            fi
        fi
    done
    echo "$count"
}

# Mark stale agents (running status but no tmux session) as failed.
# Returns count of cleaned-up agents.
cleanup_stale_agents() {
    local socket="${DISPATCH_TMUX_SOCKET:-/tmp/openclaw-coding-agents.sock}"
    local cleaned=0
    [[ -d "$RUNS_DIR" ]] || { echo "$cleaned"; return; }

    for run_file in "$RUNS_DIR"/*.json; do
        [[ -f "$run_file" ]] || continue
        local status session bead
        status="$(json_field_or_default "$run_file" '.status // "unknown"' "unknown" "run status")"
        [[ "$status" == "running" ]] || continue
        session="$(json_field_or_default "$run_file" '.session_name // ""' "" "session name")"
        bead="$(json_field_or_default "$run_file" '.bead // ""' "" "bead id")"
        [[ -n "$session" && -n "$bead" ]] || continue

        if ! tmux_session_exists "$socket" "$session"; then
            echo "Stale agent detected: $bead (session '$session' gone)" >&2
            local ts tmp
            ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            # Update run record
            tmp="$(mktemp "${run_file}.tmp.XXXXXX")"
            if jq --arg ts "$ts" '.status = "failed" | .failure_reason = "session-disappeared" | .finished_at = $ts' "$run_file" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$run_file"
            else
                rm -f "$tmp"
            fi
            # Update result record
            local result_file="$RESULTS_DIR/$bead.json"
            if [[ -f "$result_file" ]]; then
                tmp="$(mktemp "${result_file}.tmp.XXXXXX")"
                if jq --arg ts "$ts" '.status = "failed" | .reason = "session-disappeared" | .finished_at = $ts' "$result_file" > "$tmp" 2>/dev/null; then
                    mv "$tmp" "$result_file"
                else
                    rm -f "$tmp"
                fi
            fi
            cleaned=$((cleaned + 1))
            log_event "stale_agent_cleanup" "bead=$bead" "session=$session"
        fi
    done
    echo "$cleaned"
}

get_pending_beads() {
    # Source work from three places (priority order):
    # 1. Plan files in state/plans/ (pre-decomposed tasks with dispatch metadata)
    # 2. Open beads from br CLI (todo status, sorted by priority)
    # 3. Falls back to empty if neither source has work

    local pending="[]"

    # Try plan files first (structured dispatch-ready tasks)
    if [[ -d "$PLANS_DIR" ]]; then
        local plan_items
        plan_items=$(
            find "$PLANS_DIR" -name "*.json" -type f | while read -r plan; do
                local status
                status="$(json_field_or_default "$plan" '.status // "pending"' "unknown" "plan status")"
                if [[ "$status" == "pending" ]]; then
                    if jq -e '.' "$plan" >/dev/null; then
                        jq '.' "$plan"
                    else
                        echo "Warning: skipping invalid plan JSON: $plan" >&2
                    fi
                fi
            done | jq -s '.'
        )

        if [[ "$plan_items" != "[]" && -n "$plan_items" ]]; then
            echo "$plan_items"
            return
        fi
    fi

    # Fall back to br CLI for open beads
    if command -v br &>/dev/null; then
        local br_output
        if ! br_output="$(br list --json)"; then
            echo "Warning: br list --json failed; using empty bead list" >&2
            br_output="[]"
        fi

        if [[ -n "$br_output" && "$br_output" != "[]" ]]; then
            # Filter to todo/active beads sorted by priority
            if ! pending="$(echo "$br_output" | jq '[.[] | select(.status == "todo" or .status == "open")] | sort_by(.priority)')"; then
                echo "Warning: br list output was invalid JSON; using empty pending list" >&2
                pending="[]"
            fi
            echo "$pending"
            return
        fi
    fi

    echo "[]"
}

check_calibration_confidence() {
    local template="$1"
    local agent="$2"

    # Query calibration patterns
    if [[ ! -x "$WORKSPACE_ROOT/scripts/calibrate.sh" ]]; then
        echo "medium" # default if calibrate.sh not available
        return
    fi

    # Check if this template+agent combo has high reject rate
    local patterns
    patterns="$(load_calibration_patterns)"

    # Extract reject rate for this template
    local reject_rate
    if ! reject_rate="$(echo "$patterns" | jq -r ".by_template.\"$template\".reject_rate // 0")"; then
        echo "Warning: failed to parse reject rate for template '$template'" >&2
        reject_rate="0"
    fi

    # Keep signature consistent for future per-agent confidence tuning.
    : "$agent"

    # Convert to percentage comparison (awk handles float)
    if awk "BEGIN {exit !($reject_rate > 0.5)}"; then
        echo "low"
    elif awk "BEGIN {exit !($reject_rate > 0.3)}"; then
        echo "medium"
    else
        echo "high"
    fi
}

should_skip_category() {
    local template="$1"

    if [[ ! -x "$WORKSPACE_ROOT/scripts/calibrate.sh" ]]; then
        return 1 # don't skip if calibrate.sh not available
    fi

    local patterns
    patterns="$(load_calibration_patterns)"

    local reject_rate
    if ! reject_rate="$(echo "$patterns" | jq -r ".by_template.\"$template\".reject_rate // 0")"; then
        echo "Warning: failed to parse reject rate for template '$template'" >&2
        reject_rate="0"
    fi

    local count
    if ! count="$(echo "$patterns" | jq -r ".by_template.\"$template\".total // 0")"; then
        echo "Warning: failed to parse sample count for template '$template'" >&2
        count="0"
    fi

    # Skip if reject rate > 50% and at least 3 judgments
    if [[ "$count" -ge 3 ]] && awk "BEGIN {exit !($reject_rate > 0.5)}"; then
        return 0 # should skip
    fi

    return 1 # don't skip
}
