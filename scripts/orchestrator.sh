#!/usr/bin/env bash
set -euo pipefail

# Overnight autonomous orchestrator for the swarm coding factory
# Reads state, makes decisions, dispatches agents with safety guardrails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$WORKSPACE_ROOT/state"
RUNS_DIR="$STATE_DIR/runs"
RESULTS_DIR="$STATE_DIR/results"
PLANS_DIR="$STATE_DIR/plans"
CALIBRATION_DIR="$STATE_DIR/calibration"
LOG_FILE="$STATE_DIR/orchestrator-log.jsonl"
STOP_SENTINEL="$STATE_DIR/orchestrator-stop"

# Configurable limits
if [[ -v ORCH_MAX_AGENTS ]]; then
    ORCH_MAX_AGENTS="${ORCH_MAX_AGENTS:?ORCH_MAX_AGENTS cannot be empty}"
else
    ORCH_MAX_AGENTS="4"
fi
if [[ -v ORCH_MAX_HOURS ]]; then
    ORCH_MAX_HOURS="${ORCH_MAX_HOURS:?ORCH_MAX_HOURS cannot be empty}"
else
    ORCH_MAX_HOURS="8"
fi
if [[ -v ORCH_MAX_TASKS ]]; then
    ORCH_MAX_TASKS="${ORCH_MAX_TASKS:?ORCH_MAX_TASKS cannot be empty}"
else
    ORCH_MAX_TASKS="20"
fi

for numeric_var in ORCH_MAX_AGENTS ORCH_MAX_HOURS ORCH_MAX_TASKS; do
    if [[ ! "${!numeric_var}" =~ ^[0-9]+$ ]]; then
        echo "Error: $numeric_var must be a positive integer (got: ${!numeric_var})" >&2
        exit 1
    fi
done

ORCH_LIB_DIR="$SCRIPT_DIR/orchestrator"
source "$ORCH_LIB_DIR/common.sh"
source "$ORCH_LIB_DIR/commands.sh"
source "$ORCH_LIB_DIR/run.sh"

# Main command dispatch
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    run)
        orchestrate_run "$@"
        ;;
    dry-run)
        orchestrate_dry_run "$@"
        ;;
    status)
        orchestrate_status
        ;;
    stop)
        orchestrate_stop
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'" >&2
        usage
        exit 1
        ;;
esac
