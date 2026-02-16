#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMAS_DIR="$WORKSPACE_ROOT/state/schemas"

usage() {
    cat << EOF
Usage: validate-state.sh [OPTIONS] [PATH]

Validate JSON state files against their schemas.

OPTIONS:
    --runs [PATH]      Validate run records (default: state/runs/)
    --results [PATH]   Validate result records (default: state/results/)
    --all              Validate both runs and results
    --fix              Migrate legacy records (add missing nullable fields)
    --help             Show this help message

EXAMPLES:
    validate-state.sh --runs
    validate-state.sh --runs state/runs/bd-abc.json
    validate-state.sh --all
    validate-state.sh --fix --runs
EOF
}

# Parse arguments
MODE=""
TARGET_PATH=""
FIX_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --runs)
            MODE="runs"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                TARGET_PATH="$1"
                shift
            fi
            ;;
        --results)
            MODE="results"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                TARGET_PATH="$1"
                shift
            fi
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --fix)
            FIX_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "Error: Must specify --runs, --results, or --all" >&2
    usage
    exit 1
fi

# Validate a run record using jq
validate_run_record() {
    local file="$1"
    local errors=0

    # Check required fields
    local required_fields=("schema_version" "bead" "agent" "model" "repo" "prompt" "prompt_hash" "started_at" "finished_at" "duration_seconds" "status" "attempt" "max_retries" "session_name" "result_file" "exit_code" "prompt_full")

    for field in "${required_fields[@]}"; do
        if ! jq -e "has(\"$field\")" "$file" >/dev/null 2>&1; then
            echo "  Missing required field: $field" >&2
            ((errors++))
        fi
    done

    # Validate field types and values
    if ! jq -e '.schema_version == 1' "$file" >/dev/null 2>&1; then
        echo "  schema_version must be 1" >&2
        ((errors++))
    fi

    if ! jq -e '.agent | IN("claude", "codex")' "$file" >/dev/null 2>&1; then
        echo "  agent must be 'claude' or 'codex'" >&2
        ((errors++))
    fi

    if ! jq -e '.status | IN("running", "done", "failed", "timeout")' "$file" >/dev/null 2>&1; then
        echo "  status must be one of: running, done, failed, timeout" >&2
        ((errors++))
    fi

    if ! jq -e '.prompt_hash | test("^[a-f0-9]{64}$")' "$file" >/dev/null 2>&1; then
        echo "  prompt_hash must be a 64-character hex string" >&2
        ((errors++))
    fi

    return $errors
}

# Validate a result record using jq
validate_result_record() {
    local file="$1"
    local errors=0

    # Check required fields
    local required_fields=("schema_version" "bead" "agent" "status" "reason" "started_at" "finished_at" "duration_seconds" "attempt" "max_retries" "will_retry" "exit_code" "session_name")

    for field in "${required_fields[@]}"; do
        if ! jq -e "has(\"$field\")" "$file" >/dev/null 2>&1; then
            echo "  Missing required field: $field" >&2
            ((errors++))
        fi
    done

    # Validate field types and values
    if ! jq -e '.schema_version == 1' "$file" >/dev/null 2>&1; then
        echo "  schema_version must be 1" >&2
        ((errors++))
    fi

    if ! jq -e '.agent | IN("claude", "codex")' "$file" >/dev/null 2>&1; then
        echo "  agent must be 'claude' or 'codex'" >&2
        ((errors++))
    fi

    if ! jq -e '.status | IN("running", "done", "failed", "timeout")' "$file" >/dev/null 2>&1; then
        echo "  status must be one of: running, done, failed, timeout" >&2
        ((errors++))
    fi

    if ! jq -e '.will_retry | type == "boolean"' "$file" >/dev/null 2>&1; then
        echo "  will_retry must be a boolean" >&2
        ((errors++))
    fi

    return $errors
}

# Validate a single file against a schema
validate_file() {
    local file="$1"
    local schema_name="$2"

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi

    # Check if file is valid JSON
    local jq_error
    if ! jq_error="$(jq empty "$file" 2>&1 >/dev/null)"; then
        echo "FAIL: $file is not valid JSON" >&2
        [[ -n "$jq_error" ]] && echo "  jq: $jq_error" >&2
        return 1
    fi

    # Validate based on schema type
    local errors=0
    if [[ "$schema_name" == "run" ]]; then
        validate_run_record "$file" || errors=$?
    elif [[ "$schema_name" == "result" ]]; then
        validate_result_record "$file" || errors=$?
    fi

    if [[ $errors -gt 0 ]]; then
        echo "FAIL: $file has $errors validation error(s)" >&2
        return 1
    fi

    return 0
}

# Fix legacy records by adding missing nullable fields
fix_record() {
    local file="$1"
    local type="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Create backup
    cp "$file" "${file}.bak"

    # Add missing nullable fields based on type
    if [[ "$type" == "run" ]]; then
        jq '. + {
            output_summary: (if has("output_summary") then .output_summary else null end),
            failure_reason: (if has("failure_reason") then .failure_reason else null end),
            template_name: (if has("template_name") then .template_name else null end),
            prompt_full: (if has("prompt_full") then .prompt_full else .prompt end)
        }' "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    elif [[ "$type" == "result" ]]; then
        jq '. + {
            output_summary: (if has("output_summary") then .output_summary else null end)
        }' "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    fi
}

# Validate runs directory
validate_runs() {
    local runs_path="${1:-$WORKSPACE_ROOT/state/runs}"
    local failed=0
    local passed=0

    if [[ -f "$runs_path" ]]; then
        # Single file
        if $FIX_MODE; then
            fix_record "$runs_path" "run"
        fi
        if validate_file "$runs_path" "run"; then
            ((passed++))
        else
            ((failed++))
        fi
    elif [[ -d "$runs_path" ]]; then
        # Directory
        for file in "$runs_path"/*.json; do
            [[ -f "$file" ]] || continue
            if $FIX_MODE; then
                fix_record "$file" "run"
            fi
            if validate_file "$file" "run"; then
                ((passed++))
            else
                ((failed++))
            fi
        done
    else
        echo "Error: Path not found: $runs_path" >&2
        return 1
    fi

    echo "Run records: $passed passed, $failed failed" >&2
    return $failed
}

# Validate results directory
validate_results() {
    local results_path="${1:-$WORKSPACE_ROOT/state/results}"
    local failed=0
    local passed=0

    if [[ -f "$results_path" ]]; then
        # Single file
        if $FIX_MODE; then
            fix_record "$results_path" "result"
        fi
        if validate_file "$results_path" "result"; then
            ((passed++))
        else
            ((failed++))
        fi
    elif [[ -d "$results_path" ]]; then
        # Directory
        for file in "$results_path"/*.json; do
            [[ -f "$file" ]] || continue
            if $FIX_MODE; then
                fix_record "$file" "result"
            fi
            if validate_file "$file" "result"; then
                ((passed++))
            else
                ((failed++))
            fi
        done
    else
        echo "Error: Path not found: $results_path" >&2
        return 1
    fi

    echo "Result records: $passed passed, $failed failed" >&2
    return $failed
}

# Main execution
EXIT_CODE=0

case "$MODE" in
    runs)
        validate_runs "$TARGET_PATH" || EXIT_CODE=1
        ;;
    results)
        validate_results "$TARGET_PATH" || EXIT_CODE=1
        ;;
    all)
        validate_runs || EXIT_CODE=1
        validate_results || EXIT_CODE=1
        ;;
esac

exit $EXIT_CODE
