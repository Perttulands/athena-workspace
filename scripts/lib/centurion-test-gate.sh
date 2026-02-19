# shellcheck shell=bash
# centurion-test-gate.sh — Shared test gate runner for centurion scripts
# Source this file; do not execute directly.

LINT_GATE_LAST_OUTPUT=""

run_lint_gate() {
    local repo_path="$1"
    local output_file
    local lint_cmd=""
    local -a shell_files=()

    output_file="$(mktemp)"
    LINT_GATE_LAST_OUTPUT=""

    # Go: prefer golangci-lint, fall back to go vet.
    if [[ -f "$repo_path/go.mod" ]]; then
        if command -v golangci-lint >/dev/null 2>&1; then
            lint_cmd="golangci-lint run"
            if ! (cd "$repo_path" && golangci-lint run) >"$output_file" 2>&1; then
                LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
                rm -f "$output_file"
                echo "Lint gate failed: $lint_cmd" >&2
                echo "$LINT_GATE_LAST_OUTPUT" >&2
                return 1
            fi
        else
            lint_cmd="go vet ./..."
            if ! (cd "$repo_path" && go vet ./...) >"$output_file" 2>&1; then
                LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
                rm -f "$output_file"
                echo "Lint gate failed: $lint_cmd" >&2
                echo "$LINT_GATE_LAST_OUTPUT" >&2
                return 1
            fi
        fi
        echo "Lint gate passed: $lint_cmd"
    fi

    # JS/TS: run eslint only when the repo declares eslint in package.json.
    if [[ -f "$repo_path/package.json" ]]; then
        local has_eslint=1
        if command -v jq >/dev/null 2>&1; then
            jq -e \
                '.dependencies.eslint != null
                 or .devDependencies.eslint != null
                 or .scripts.eslint != null
                 or ((.scripts.lint // "") | contains("eslint"))' \
                "$repo_path/package.json" >/dev/null || has_eslint=0
        else
            rg -q '"eslint"' "$repo_path/package.json" || has_eslint=0
        fi

        if [[ "$has_eslint" -eq 1 ]]; then
            lint_cmd="eslint ."
            if [[ -x "$repo_path/node_modules/.bin/eslint" ]]; then
                if ! (cd "$repo_path" && ./node_modules/.bin/eslint .) >"$output_file" 2>&1; then
                    LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
                    rm -f "$output_file"
                    echo "Lint gate failed: $lint_cmd" >&2
                    echo "$LINT_GATE_LAST_OUTPUT" >&2
                    return 1
                fi
            else
                if ! command -v npx >/dev/null 2>&1; then
                    LINT_GATE_LAST_OUTPUT="eslint is configured in package.json but npx is not available"
                    rm -f "$output_file"
                    echo "Lint gate failed: $lint_cmd" >&2
                    echo "$LINT_GATE_LAST_OUTPUT" >&2
                    return 1
                fi
                if ! (cd "$repo_path" && npx --no-install eslint .) >"$output_file" 2>&1; then
                    LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
                    rm -f "$output_file"
                    echo "Lint gate failed: $lint_cmd" >&2
                    echo "$LINT_GATE_LAST_OUTPUT" >&2
                    return 1
                fi
            fi
            echo "Lint gate passed: $lint_cmd"
        fi
    fi

    # Bash: lint shell scripts with shellcheck.
    mapfile -t shell_files < <(
        cd "$repo_path" && find . -type f -name '*.sh' \
            -not -path './.git/*' \
            -not -path './node_modules/*' \
            -not -path './vendor/*'
    )
    if [[ ${#shell_files[@]} -gt 0 ]]; then
        lint_cmd="shellcheck"
        if ! command -v shellcheck >/dev/null 2>&1; then
            echo "Lint gate skipped: shellcheck not installed"
            rm -f "$output_file"
            return 0
        fi
        if ! (cd "$repo_path" && shellcheck "${shell_files[@]}") >"$output_file" 2>&1; then
            LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
            rm -f "$output_file"
            echo "Lint gate failed: $lint_cmd" >&2
            echo "$LINT_GATE_LAST_OUTPUT" >&2
            return 1
        fi
        echo "Lint gate passed: $lint_cmd"
    fi

    rm -f "$output_file"
    return 0
}

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
        rm -f "$output_file"
        echo "Test gate passed: $runner_label"
        
        # Run truthsayer scan if available
        if command -v truthsayer >/dev/null 2>&1 || [[ -x "$HOME/go/bin/truthsayer" ]]; then
            local ts_bin="${TRUTHSAYER_BIN:-${HOME}/go/bin/truthsayer}"
            [[ -x "$ts_bin" ]] || ts_bin="truthsayer"
            
            local ts_output
            ts_output="$("$ts_bin" scan "$repo_path" --severity error 2>&1)" || {
                local ts_exit=$?
                TEST_GATE_LAST_OUTPUT="Truthsayer scan failed:
$ts_output"
                echo "Truthsayer gate failed (exit $ts_exit)" >&2
                echo "$ts_output" >&2
                return 1
            }
            echo "Truthsayer gate passed"
        fi

        if ! run_lint_gate "$repo_path"; then
            TEST_GATE_LAST_OUTPUT="Lint checks failed:
$LINT_GATE_LAST_OUTPUT"
            return 1
        fi
        
        TEST_GATE_LAST_OUTPUT=""
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
