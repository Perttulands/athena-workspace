# shellcheck shell=bash

orchestrate_run() {
    local max_hours="$ORCH_MAX_HOURS"
    local max_tasks="$ORCH_MAX_TASKS"
    local repo_path=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-hours)
                max_hours="$2"
                shift 2
                ;;
            --max-tasks)
                max_tasks="$2"
                shift 2
                ;;
            --repo)
                repo_path="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Remove stop sentinel if exists
    rm -f "$STOP_SENTINEL"

    # Signal handling: create stop sentinel on SIGTERM/SIGINT for graceful shutdown
    trap 'echo "Signal received, creating stop sentinel..."; touch "$STOP_SENTINEL"; log_event "orchestrator_signal" "reason=signal-received"' SIGTERM SIGINT SIGHUP

    # Initialize
    mkdir -p "$STATE_DIR" "$RUNS_DIR" "$RESULTS_DIR"
    local start_time
    start_time=$(date +%s)
    local max_end_time=$((start_time + max_hours * 3600))
    local tasks_completed=0
    local consecutive_failures=0
    local max_consecutive_failures=5

    log_event "orchestrator_start" "max_hours=$max_hours" "max_tasks=$max_tasks" "repo=$repo_path"

    echo "Starting orchestrator..."
    echo "  Max hours: $max_hours"
    echo "  Max tasks: $max_tasks"
    echo "  Max concurrent agents: $ORCH_MAX_AGENTS"
    echo ""

    # Clean up any stale agents from previous runs
    local stale_count
    stale_count="$(cleanup_stale_agents)"
    if [[ "$stale_count" -gt 0 ]]; then
        echo "Cleaned up $stale_count stale agent(s) from previous runs"
    fi

    # Approval gate: preview work before dispatching
    local pending_preview
    pending_preview=$(get_pending_beads)
    local preview_count
    if ! preview_count="$(echo "$pending_preview" | jq 'length')"; then
        echo "Warning: pending work preview was not valid JSON; treating as empty queue" >&2
        preview_count="0"
    fi

    if [[ $preview_count -eq 0 ]]; then
        echo "No pending work found. Nothing to orchestrate."
        log_event "orchestrator_stop" "reason=no_work_at_start"
        return 0
    fi

    echo "=== APPROVAL GATE ==="
    echo "Found $preview_count pending task(s):"
    if ! echo "$pending_preview" | jq -r '.[] | "  - \(.id // .bead_id // "unknown"): \(.title // .description // "untitled") [P\(.priority // "?")]"'; then
        echo "  (could not parse task details)"
    fi
    echo ""

    # Auto-approve if ORCH_AUTO_APPROVE is set to true, otherwise require confirmation
    local auto_approve="false"
    if [[ -v ORCH_AUTO_APPROVE ]]; then
        auto_approve="$ORCH_AUTO_APPROVE"
    fi
    if [[ "$auto_approve" != "true" ]]; then
        echo "Approve dispatching these tasks? [y/N]"
        read -r -t 30 approval || approval="n"
        if [[ "$approval" != "y" && "$approval" != "Y" ]]; then
            echo "Orchestrator not approved. Exiting."
            log_event "orchestrator_stop" "reason=not_approved" "pending=$preview_count"
            return 0
        fi
    else
        echo "Auto-approved (ORCH_AUTO_APPROVE=true)"
    fi
    echo "====================="
    echo ""

    # Main loop
    local loop_iteration=0
    while true; do
        loop_iteration=$((loop_iteration + 1))

        # Check stop conditions
        if [[ -f "$STOP_SENTINEL" ]]; then
            echo "Stop sentinel detected, shutting down..."
            log_event "orchestrator_stop" "reason=sentinel" "tasks_completed=$tasks_completed"
            break
        fi

        local current_time
        current_time=$(date +%s)
        if [[ $current_time -ge $max_end_time ]]; then
            echo "Max hours reached ($max_hours h), shutting down..."
            log_event "orchestrator_stop" "reason=max_hours" "tasks_completed=$tasks_completed"
            break
        fi

        if [[ $tasks_completed -ge $max_tasks ]]; then
            echo "Max tasks reached ($max_tasks), shutting down..."
            log_event "orchestrator_stop" "reason=max_tasks" "tasks_completed=$tasks_completed"
            break
        fi

        if [[ $consecutive_failures -ge $max_consecutive_failures ]]; then
            echo "Too many consecutive dispatch failures ($consecutive_failures), shutting down..." >&2
            log_event "orchestrator_stop" "reason=consecutive_failures" "tasks_completed=$tasks_completed" "failures=$consecutive_failures"
            break
        fi

        # Periodic stale agent cleanup (every 10 iterations)
        if (( loop_iteration % 10 == 0 )); then
            stale_count="$(cleanup_stale_agents)"
            if [[ "$stale_count" -gt 0 ]]; then
                echo "Cleaned up $stale_count stale agent(s)"
            fi
        fi

        # Check disk space
        if ! check_disk_space "$WORKSPACE_ROOT" 200 2>/dev/null; then
            echo "Disk space critically low, shutting down..." >&2
            log_event "orchestrator_stop" "reason=disk_space" "tasks_completed=$tasks_completed"
            break
        fi

        # Heartbeat log (every 10 iterations)
        if (( loop_iteration % 10 == 0 )); then
            local elapsed_hours=$(( (current_time - start_time) / 3600 ))
            local active_now
            active_now="$(count_active_agents)"
            log_event "heartbeat" "tasks_completed=$tasks_completed" "active=$active_now" "elapsed_hours=$elapsed_hours" "iteration=$loop_iteration"
        fi

        # Check active agents
        local active
        active=$(count_active_agents)

        if [[ $active -ge $ORCH_MAX_AGENTS ]]; then
            sleep 10
            continue
        fi

        # Get pending work
        local pending
        pending=$(get_pending_beads)
        local pending_count
        if ! pending_count=$(echo "$pending" | jq 'length' 2>/dev/null); then
            echo "Warning: failed to parse pending beads, retrying..." >&2
            sleep 10
            continue
        fi

        if [[ $pending_count -eq 0 ]]; then
            # Check if agents are still running — if so, wait for them
            if [[ $active -gt 0 ]]; then
                sleep 15
                continue
            fi
            echo "No pending work and no active agents, shutting down..."
            log_event "orchestrator_stop" "reason=no_work" "tasks_completed=$tasks_completed"
            break
        fi

        echo "[$(date -u +%H:%M:%S)] Active: $active | Pending: $pending_count | Completed: $tasks_completed"

        # Select next bead (first in priority-sorted list)
        local next_bead
        next_bead=$(echo "$pending" | jq '.[0]')
        local bead_id
        bead_id=$(echo "$next_bead" | jq -r '.id // .bead_id // empty')
        local bead_title
        bead_title=$(echo "$next_bead" | jq -r '.title // .description // "untitled"')
        local bead_priority
        bead_priority=$(echo "$next_bead" | jq -r '.priority // "2"')

        if [[ -z "$bead_id" ]]; then
            echo "Could not extract bead ID from pending work, skipping..."
            sleep 10
            continue
        fi

        echo "Next bead: $bead_id - $bead_title (P$bead_priority)"

        # Check calibration confidence for this type of work
        local confidence
        confidence=$(check_calibration_confidence "feature" "claude")
        if should_skip_category "feature" "claude"; then
            echo "Skipping $bead_id — calibration indicates high reject rate"
            log_event "bead_skipped" "bead=$bead_id" "reason=calibration"
            sleep 5
            continue
        fi

        # Keep variable for logging/inspection while behavior stays unchanged.
        : "$confidence"

        # Select agent type based on priority
        local agent_type="claude"
        if [[ "$bead_priority" == "0" ]]; then
            agent_type="codex" # P0 gets codex for complex work
        fi

        # Determine repo path
        local dispatch_repo="${repo_path:-$WORKSPACE_ROOT}"

        # Build prompt from bead metadata
        local prompt="Fix/implement: $bead_title (bead: $bead_id, priority: P$bead_priority)"

        # Dispatch via dispatch.sh
        echo "Dispatching $bead_id to $agent_type..."
        log_event "bead_dispatched" "bead=$bead_id" "agent=$agent_type" "title=$bead_title"

        if "$SCRIPT_DIR/dispatch.sh" "$bead_id" "$dispatch_repo" "$agent_type" "$prompt"; then
            echo "Successfully dispatched $bead_id"
            tasks_completed=$((tasks_completed + 1))
            consecutive_failures=0
        else
            echo "Failed to dispatch $bead_id" >&2
            log_event "dispatch_failed" "bead=$bead_id" "agent=$agent_type"
            consecutive_failures=$((consecutive_failures + 1))
        fi

        # Wait before next dispatch to avoid resource contention
        sleep 15
    done

    echo ""
    echo "Orchestrator stopped."
    echo "  Tasks completed: $tasks_completed"
    echo "  Runtime: $(( ($(date +%s) - start_time) / 60 )) minutes"
    echo "  Consecutive failures at exit: $consecutive_failures"
    log_event "orchestrator_complete" "tasks_completed=$tasks_completed" "runtime_minutes=$(( ($(date +%s) - start_time) / 60 ))"
}
