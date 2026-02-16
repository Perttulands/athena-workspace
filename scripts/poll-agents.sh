#!/usr/bin/env bash
set -euo pipefail

# poll-agents.sh — Show status of all agent sessions and detect stale agents
#
# Usage: poll-agents.sh [--json]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

SOCKET="${DISPATCH_TMUX_SOCKET:-/tmp/openclaw-coding-agents.sock}"
RUNS_DIR="$WORKSPACE_ROOT/state/runs"
RESULTS_DIR="$WORKSPACE_ROOT/state/results"
JSON_OUTPUT=false

[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

# Collect session info
sessions=""
if [[ -S "$SOCKET" ]]; then
    sessions="$(tmux -S "$SOCKET" list-sessions -F "#{session_name}" 2>/dev/null)" || sessions=""
fi

# Collect run record info
declare -A run_status=()
declare -A run_bead=()
declare -A run_agent=()
declare -A run_model=()
declare -A run_started=()
if [[ -d "$RUNS_DIR" ]]; then
    for run_file in "$RUNS_DIR"/*.json; do
        [[ -f "$run_file" ]] || continue
        local_bead="$(jq -r '.bead // empty' "$run_file" 2>/dev/null)" || continue
        [[ -n "$local_bead" ]] || continue
        local_session="$(jq -r '.session_name // empty' "$run_file" 2>/dev/null)" || local_session=""
        local_status="$(jq -r '.status // "unknown"' "$run_file" 2>/dev/null)" || local_status="unknown"
        local_agent="$(jq -r '.agent // "?"' "$run_file" 2>/dev/null)" || local_agent="?"
        local_model="$(jq -r '.model // "?"' "$run_file" 2>/dev/null)" || local_model="?"
        local_started="$(jq -r '.started_at // "?"' "$run_file" 2>/dev/null)" || local_started="?"
        [[ -n "$local_session" ]] && run_status["$local_session"]="$local_status"
        [[ -n "$local_session" ]] && run_bead["$local_session"]="$local_bead"
        [[ -n "$local_session" ]] && run_agent["$local_session"]="$local_agent"
        [[ -n "$local_session" ]] && run_model["$local_session"]="$local_model"
        [[ -n "$local_session" ]] && run_started["$local_session"]="$local_started"
    done
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output mode
    json_items="[]"

    if [[ -n "$sessions" ]]; then
        while IFS= read -r session; do
            [[ -z "$session" ]] && continue
            local_pane=""
            if ! local_pane="$(tmux -S "$SOCKET" capture-pane -t "$session" -p -J -S -3 2>/dev/null)"; then
                local_pane=""
            fi
            # Detect if shell prompt visible
            local_live="true"
            if echo "$local_pane" | grep -qE '(^|[[:space:]])(\$|>|%)([[:space:]]|$)'; then
                local_live="false"
            fi
            json_items="$(echo "$json_items" | jq \
                --arg session "$session" \
                --arg bead "${run_bead[$session]:-unknown}" \
                --arg status "${run_status[$session]:-unknown}" \
                --arg agent "${run_agent[$session]:-?}" \
                --arg model "${run_model[$session]:-?}" \
                --arg started "${run_started[$session]:-?}" \
                --argjson live "$local_live" \
                '. + [{session:$session, bead:$bead, status:$status, agent:$agent, model:$model, started:$started, tmux_alive:true, agent_active:$live}]')"
        done <<< "$sessions"
    fi

    # Add stale entries (running in state but no tmux session)
    for session in "${!run_status[@]}"; do
        if [[ "${run_status[$session]}" == "running" ]]; then
            if [[ -z "$sessions" ]] || ! echo "$sessions" | grep -q "^${session}$"; then
                json_items="$(echo "$json_items" | jq \
                    --arg session "$session" \
                    --arg bead "${run_bead[$session]:-unknown}" \
                    --arg agent "${run_agent[$session]:-?}" \
                    --arg model "${run_model[$session]:-?}" \
                    --arg started "${run_started[$session]:-?}" \
                    '. + [{session:$session, bead:$bead, status:"stale", agent:$agent, model:$model, started:$started, tmux_alive:false, agent_active:false}]')"
            fi
        fi
    done

    echo "$json_items" | jq '.'
    exit 0
fi

# Human-readable output
if [[ -z "$sessions" ]] && [[ ${#run_status[@]} -eq 0 ]]; then
    echo "No active agents"
    exit 0
fi

# Show live sessions
if [[ -n "$sessions" ]]; then
    echo "=== Live Sessions ==="
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        local_pane=""
        if ! local_pane="$(tmux -S "$SOCKET" capture-pane -t "$session" -p -J -S -3 2>/dev/null)"; then
            local_pane=""
        fi

        local_status_label="RUNNING"
        if echo "$local_pane" | grep -qE '(^|[[:space:]])(\$|>|%)([[:space:]]|$)'; then
            local_status_label="DONE"
        fi

        local_bead="${run_bead[$session]:-?}"
        local_agent="${run_agent[$session]:-?}"
        local_model="${run_model[$session]:-?}"
        printf "  %-20s %s  bead=%s agent=%s/%s\n" "$session" "$local_status_label" "$local_bead" "$local_agent" "$local_model"
    done <<< "$sessions"
    echo ""
fi

# Show stale agents
stale_found=false
for session in "${!run_status[@]}"; do
    if [[ "${run_status[$session]}" == "running" ]]; then
        if [[ -z "$sessions" ]] || ! echo "$sessions" | grep -q "^${session}$"; then
            if [[ "$stale_found" == "false" ]]; then
                echo "=== Stale Agents (running in state, no tmux session) ==="
                stale_found=true
            fi
            printf "  %-20s STALE  bead=%s started=%s\n" "$session" "${run_bead[$session]:-?}" "${run_started[$session]:-?}"
        fi
    fi
done
[[ "$stale_found" == "true" ]] && echo ""

# Show recent results
if [[ -d "$RESULTS_DIR" ]]; then
    recent_results="$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | head -5)" || recent_results=""
    if [[ -n "$recent_results" ]]; then
        echo "=== Recent Results (last 5) ==="
        while IFS= read -r result_file; do
            [[ -f "$result_file" ]] || continue
            local_bead="$(jq -r '.bead // "?"' "$result_file" 2>/dev/null)" || local_bead="?"
            local_status="$(jq -r '.status // "?"' "$result_file" 2>/dev/null)" || local_status="?"
            local_reason="$(jq -r '.reason // ""' "$result_file" 2>/dev/null)" || local_reason=""
            local_duration="$(jq -r '.duration_seconds // "?"' "$result_file" 2>/dev/null)" || local_duration="?"
            printf "  %-10s %-8s %ss  %s\n" "$local_bead" "$local_status" "$local_duration" "$local_reason"
        done <<< "$recent_results"
        echo ""
    fi
fi
