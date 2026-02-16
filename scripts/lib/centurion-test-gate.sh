# shellcheck shell=bash
# centurion-test-gate.sh — Shared test gate runner for centurion scripts
# Source this file; do not execute directly.

run_test_gate() {
    local repo_path="$1"
    local timeout_seconds=300
    local configured_test_cmd=""
    local configured_timeout=""
    local runner_label=""
    local -a test_cmd=()

    if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        configured_test_cmd="$(jq -r --arg repo "$repo_path" '.repos[$repo].test_cmd // empty' "$CONFIG_FILE")"
        configured_timeout="$(jq -r --arg repo "$repo_path" '.repos[$repo].timeout // empty' "$CONFIG_FILE")"
    fi

    if [[ -n "$configured_timeout" ]] && is_integer "$configured_timeout"; then
        timeout_seconds="$configured_timeout"
    fi

    if [[ -n "$configured_test_cmd" ]]; then
        test_cmd=(bash -lc "$configured_test_cmd")
        runner_label="$configured_test_cmd"
    elif [[ -f "$repo_path/package.json" ]]; then
        test_cmd=(npm test)
        runner_label="npm test"
    elif [[ -f "$repo_path/go.mod" ]]; then
        test_cmd=(go test ./...)
        runner_label="go test ./..."
    elif [[ -f "$repo_path/Cargo.toml" ]]; then
        test_cmd=(cargo test)
        runner_label="cargo test"
    else
        echo "No supported test runner detected in $repo_path; skipping test gate"
        TEST_GATE_LAST_OUTPUT=""
        return 0
    fi

    local output_file
    output_file="$(mktemp)"

    if (cd "$repo_path" && timeout "$timeout_seconds" "${test_cmd[@]}") >"$output_file" 2>&1; then
        TEST_GATE_LAST_OUTPUT=""
        rm -f "$output_file"
        echo "Test gate passed: $runner_label"
        return 0
    else
        local exit_code=$?
        TEST_GATE_LAST_OUTPUT="$(tail -n 50 "$output_file" || true)"
        rm -f "$output_file"

        echo "Test gate failed: $runner_label (exit $exit_code)" >&2
        if [[ -n "$TEST_GATE_LAST_OUTPUT" ]]; then
            echo "$TEST_GATE_LAST_OUTPUT" >&2
        fi
        return 1
    fi
}
