# shellcheck shell=bash

orchestrate_dry_run() {
    local repo_path="${1:-}"

    echo "=== Orchestrator Dry Run ==="
    echo ""
    echo "Configuration:"
    echo "  Max concurrent agents: $ORCH_MAX_AGENTS"
    echo "  Max hours: $ORCH_MAX_HOURS"
    echo "  Max tasks: $ORCH_MAX_TASKS"
    echo "  Repository: ${repo_path:-<none specified>}"
    echo ""

    echo "State:"
    echo "  Active agents: $(count_active_agents)"
    echo "  Pending beads: $(get_pending_beads | jq 'length')"
    echo ""

    echo "Would execute:"
    echo "  1. Clean up stale agents from previous runs"
    echo "  2. Check calibration patterns (call calibrate.sh patterns)"
    echo "  3. For each pending bead:"
    echo "     a. Check disk space"
    echo "     b. Check calibration confidence"
    echo "     c. Dispatch agent to shared branch (call dispatch.sh)"
    echo "     d. Log decision to orchestrator-log.jsonl"
    echo "  4. Wait for completion, verify, cleanup"
    echo "  5. Periodic: clean stale agents, heartbeat log, disk check"
    echo "  6. Repeat until limits reached or no work"
    echo ""
    echo "Safety guardrails active:"
    echo "  - Max $ORCH_MAX_AGENTS concurrent agents"
    echo "  - Stop after $ORCH_MAX_HOURS hours"
    echo "  - Stop after $ORCH_MAX_TASKS tasks"
    echo "  - Stop after 5 consecutive dispatch failures"
    echo "  - Stop on critically low disk space (<200MB)"
    echo "  - Skip categories with >50% calibration reject rate"
    echo "  - Graceful shutdown on SIGTERM/SIGINT/SIGHUP"
    echo ""
}

orchestrate_status() {
    echo "=== Orchestrator Status ==="
    echo ""
    echo "Active agents: $(count_active_agents)"
    echo "Pending beads: $(get_pending_beads | jq 'length')"
    echo ""

    if [[ -f "$STOP_SENTINEL" ]]; then
        echo "Status: STOP REQUESTED"
        echo "Stop sentinel: $STOP_SENTINEL"
    else
        echo "Status: READY"
    fi
    echo ""

    if [[ -f "$LOG_FILE" ]]; then
        echo "Recent events (last 5):"
        local recent_events
        recent_events="$(tail -5 "$LOG_FILE")"
        if ! echo "$recent_events" | jq -r '"\(.ts) \(.event) \(.bead // "n/a")"'; then
            echo "$recent_events"
        fi
    else
        echo "No orchestrator log found"
    fi
    echo ""
}

orchestrate_stop() {
    echo "Creating stop sentinel: $STOP_SENTINEL"
    mkdir -p "$STATE_DIR"
    touch "$STOP_SENTINEL"
    log_event "stop_requested" "reason=user command"
    echo "Orchestrator will stop gracefully (finish current tasks, no new tasks)"
}
