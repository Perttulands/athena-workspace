#!/usr/bin/env bash
set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -v RUNS_DIR ]]; then
    RUNS_DIR="${RUNS_DIR:?RUNS_DIR cannot be empty}"
else
    RUNS_DIR="$WORKSPACE_ROOT/state/runs"
fi
if [[ -v CALIBRATION_DIR ]]; then
    CALIBRATION_DIR="${CALIBRATION_DIR:?CALIBRATION_DIR cannot be empty}"
else
    CALIBRATION_DIR="$WORKSPACE_ROOT/state/calibration"
fi
SCHEMA_FILE="$WORKSPACE_ROOT/state/schemas/calibration.schema.json"

usage() {
    cat << EOF
Usage: calibrate.sh <command> [options]

Commands:
  record <bead-id> <accept|reject> [reason]
      Record a judgment for a completed bead

  stats
      Show accept/reject rates by template, agent, model

  export --json
      Export all calibration data as JSON

  patterns
      Identify statistically significant patterns

Options:
  --help     Show this help message

Examples:
  calibrate.sh record bd-abc accept "Clean implementation"
  calibrate.sh record bd-def reject "Missing tests"
  calibrate.sh stats
  calibrate.sh patterns
EOF
}

get_iso8601_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

list_calibration_files() {
    shopt -s nullglob
    local files=("$CALIBRATION_DIR"/*.json)
    shopt -u nullglob
    printf '%s\n' "${files[@]}"
}

has_calibration_files() {
    [[ -d "$CALIBRATION_DIR" ]] || return 1
    shopt -s nullglob
    local files=("$CALIBRATION_DIR"/*.json)
    shopt -u nullglob
    (( ${#files[@]} > 0 ))
}

unique_calibration_field_values() {
    local jq_filter="$1"
    local -a files=()
    mapfile -t files < <(list_calibration_files)
    (( ${#files[@]} > 0 )) || return 0
    jq -r "$jq_filter" "${files[@]}" | sort -u
}

record_calibration() {
    local bead_id="$1"
    local decision="$2"
    local reason="${3:-}"

    # Validate decision
    if [[ "$decision" != "accept" && "$decision" != "reject" ]]; then
        echo "Error: decision must be 'accept' or 'reject'" >&2
        return 1
    fi

    # Read run record to auto-populate run_context
    local run_file="$RUNS_DIR/$bead_id.json"
    if [[ ! -f "$run_file" ]]; then
        echo "Error: run record not found: $run_file" >&2
        return 1
    fi

    # Extract context from run record (use jq without -r to preserve JSON types)
    local agent model template_name duration_seconds verification_overall
    agent=$(jq -r '.agent' "$run_file")
    model=$(jq -r '.model' "$run_file")
    template_name=$(jq '.template_name // null' "$run_file")
    duration_seconds=$(jq '.duration_seconds // null' "$run_file")
    verification_overall=$(jq '.verification.overall // null' "$run_file")

    # Build calibration record
    local cal_file="$CALIBRATION_DIR/$bead_id.json"
    local tmp_file="$cal_file.tmp.$$"

    mkdir -p "$CALIBRATION_DIR"

    jq -n \
        --arg bead "$bead_id" \
        --arg decision "$decision" \
        --arg reason "$reason" \
        --arg decided_at "$(get_iso8601_timestamp)" \
        --arg agent "$agent" \
        --arg model "$model" \
        --argjson template_name "$template_name" \
        --argjson duration_seconds "$duration_seconds" \
        --argjson verification_overall "$verification_overall" \
        '{
            schema_version: 1,
            bead: $bead,
            decision: $decision,
            reason: ($reason | if . == "" then null else . end),
            decided_at: $decided_at,
            run_context: {
                agent: $agent,
                model: $model,
                template_name: $template_name,
                duration_seconds: $duration_seconds,
                verification_overall: $verification_overall
            }
        }' > "$tmp_file"

    # Validate against schema (advisory)
    if command -v jq >/dev/null 2>&1; then
        if ! jq -e '.schema_version == 1 and .bead and .decision and .decided_at and .run_context' "$tmp_file" >/dev/null 2>&1; then
            echo "Warning: calibration record failed basic validation" >&2
        fi
    fi

    # Atomic write
    mv "$tmp_file" "$cal_file"

    echo "Recorded: $bead_id → $decision"
    if [[ -n "$reason" ]]; then
        echo "Reason: $reason"
    fi
}

show_stats() {
    if ! has_calibration_files; then
        echo "No calibration data yet."
        return 0
    fi

    # Count total accepts/rejects
    local total=0 accepts=0 rejects=0

    for cal_file in "$CALIBRATION_DIR"/*.json; do
        [[ -f "$cal_file" ]] || continue
        total=$((total + 1))

        decision=$(jq -r '.decision' "$cal_file")
        if [[ "$decision" == "accept" ]]; then
            accepts=$((accepts + 1))
        elif [[ "$decision" == "reject" ]]; then
            rejects=$((rejects + 1))
        fi
    done

    local accept_rate=0
    if [[ $total -gt 0 ]]; then
        accept_rate=$(awk "BEGIN {printf \"%.1f\", ($accepts / $total) * 100}")
    fi

    echo "=== Calibration Statistics ==="
    echo "Total judgments: $total"
    echo "Accepts: $accepts ($accept_rate%)"
    echo "Rejects: $rejects"
    echo ""

    # By template
    echo "--- By Template ---"
    local templates
    templates="$(unique_calibration_field_values '.run_context.template_name // "null"')"

    for template in $templates; do
        local t_total=0 t_accepts=0 t_rejects=0

        for cal_file in "$CALIBRATION_DIR"/*.json; do
            [[ -f "$cal_file" ]] || continue

            local cal_template
            cal_template=$(jq -r '.run_context.template_name // "null"' "$cal_file")
            if [[ "$cal_template" == "$template" ]]; then
                t_total=$((t_total + 1))
                decision=$(jq -r '.decision' "$cal_file")
                if [[ "$decision" == "accept" ]]; then
                    t_accepts=$((t_accepts + 1))
                else
                    t_rejects=$((t_rejects + 1))
                fi
            fi
        done

        local t_accept_rate=0
        if [[ $t_total -gt 0 ]]; then
            t_accept_rate=$(awk "BEGIN {printf \"%.1f\", ($t_accepts / $t_total) * 100}")
        fi

        echo "  $template: $t_accepts/$t_total ($t_accept_rate%)"
    done

    # By agent
    echo ""
    echo "--- By Agent ---"
    local agents
    agents="$(unique_calibration_field_values '.run_context.agent')"

    for agent in $agents; do
        local a_total=0 a_accepts=0 a_rejects=0

        for cal_file in "$CALIBRATION_DIR"/*.json; do
            [[ -f "$cal_file" ]] || continue

            local cal_agent
            cal_agent=$(jq -r '.run_context.agent' "$cal_file")
            if [[ "$cal_agent" == "$agent" ]]; then
                a_total=$((a_total + 1))
                decision=$(jq -r '.decision' "$cal_file")
                if [[ "$decision" == "accept" ]]; then
                    a_accepts=$((a_accepts + 1))
                else
                    a_rejects=$((a_rejects + 1))
                fi
            fi
        done

        local a_accept_rate=0
        if [[ $a_total -gt 0 ]]; then
            a_accept_rate=$(awk "BEGIN {printf \"%.1f\", ($a_accepts / $a_total) * 100}")
        fi

        echo "  $agent: $a_accepts/$a_total ($a_accept_rate%)"
    done

    # By model
    echo ""
    echo "--- By Model ---"
    local models
    models="$(unique_calibration_field_values '.run_context.model')"

    for model in $models; do
        local m_total=0 m_accepts=0 m_rejects=0

        for cal_file in "$CALIBRATION_DIR"/*.json; do
            [[ -f "$cal_file" ]] || continue

            local cal_model
            cal_model=$(jq -r '.run_context.model' "$cal_file")
            if [[ "$cal_model" == "$model" ]]; then
                m_total=$((m_total + 1))
                decision=$(jq -r '.decision' "$cal_file")
                if [[ "$decision" == "accept" ]]; then
                    m_accepts=$((m_accepts + 1))
                else
                    m_rejects=$((m_rejects + 1))
                fi
            fi
        done

        local m_accept_rate=0
        if [[ $m_total -gt 0 ]]; then
            m_accept_rate=$(awk "BEGIN {printf \"%.1f\", ($m_accepts / $m_total) * 100}")
        fi

        echo "  $model: $m_accepts/$m_total ($m_accept_rate%)"
    done
}

export_json() {
    if ! has_calibration_files; then
        echo "[]"
        return 0
    fi

    local -a files=()
    mapfile -t files < <(list_calibration_files)
    if ! jq -s '.' "${files[@]}"; then
        echo "Warning: failed to export calibration JSON, returning empty array" >&2
        echo "[]"
    fi
}

identify_patterns() {
    if ! has_calibration_files; then
        echo "No calibration data yet."
        return 0
    fi

    echo "=== Calibration Patterns ==="
    echo ""

    local found_patterns=0

    # Check templates with >3 judgments and reject rate >40%
    local templates
    templates="$(unique_calibration_field_values '.run_context.template_name // "null"')"

    for template in $templates; do
        local t_total=0 t_rejects=0

        for cal_file in "$CALIBRATION_DIR"/*.json; do
            [[ -f "$cal_file" ]] || continue

            local cal_template
            cal_template=$(jq -r '.run_context.template_name // "null"' "$cal_file")
            if [[ "$cal_template" == "$template" ]]; then
                t_total=$((t_total + 1))
                decision=$(jq -r '.decision' "$cal_file")
                if [[ "$decision" == "reject" ]]; then
                    t_rejects=$((t_rejects + 1))
                fi
            fi
        done

        if [[ $t_total -ge 3 ]]; then
            local reject_rate
            reject_rate=$(awk "BEGIN {print ($t_rejects / $t_total) * 100}")
            if awk "BEGIN {exit !($reject_rate > 40)}"; then
                echo "⚠ Template '$template': $t_rejects/$t_total rejections (${reject_rate}%)"
                echo "   Recommendation: Revise template or avoid for this task type"
                found_patterns=$((found_patterns + 1))
            fi
        fi
    done

    # Check agents with >3 judgments and reject rate >40%
    local agents
    agents="$(unique_calibration_field_values '.run_context.agent')"

    for agent in $agents; do
        local a_total=0 a_rejects=0

        for cal_file in "$CALIBRATION_DIR"/*.json; do
            [[ -f "$cal_file" ]] || continue

            local cal_agent
            cal_agent=$(jq -r '.run_context.agent' "$cal_file")
            if [[ "$cal_agent" == "$agent" ]]; then
                a_total=$((a_total + 1))
                decision=$(jq -r '.decision' "$cal_file")
                if [[ "$decision" == "reject" ]]; then
                    a_rejects=$((a_rejects + 1))
                fi
            fi
        done

        if [[ $a_total -ge 3 ]]; then
            local reject_rate
            reject_rate=$(awk "BEGIN {print ($a_rejects / $a_total) * 100}")
            if awk "BEGIN {exit !($reject_rate > 40)}"; then
                echo "⚠ Agent '$agent': $a_rejects/$a_total rejections (${reject_rate}%)"
                echo "   Recommendation: Review agent configuration or prompt templates"
                found_patterns=$((found_patterns + 1))
            fi
        fi
    done

    if [[ $found_patterns -eq 0 ]]; then
        echo "No significant patterns detected yet (need 3+ judgments with >40% reject rate)"
    fi
}

# Main command dispatcher
if [[ $# -eq 0 ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

command="$1"
shift

case "$command" in
    record)
        if [[ $# -lt 2 ]]; then
            echo "Error: record requires <bead-id> <accept|reject> [reason]" >&2
            exit 1
        fi
        record_calibration "$@"
        ;;
    stats)
        show_stats
        ;;
    export)
        if [[ "${1:-}" == "--json" ]]; then
            export_json
        else
            echo "Error: export requires --json flag" >&2
            exit 1
        fi
        ;;
    patterns)
        identify_patterns
        ;;
    *)
        echo "Error: unknown command: $command" >&2
        usage
        exit 1
        ;;
esac
