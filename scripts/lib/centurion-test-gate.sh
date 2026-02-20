# shellcheck shell=bash
# centurion-test-gate.sh — Shared quality gate runner for centurion scripts
# Source this file; do not execute directly.

LINT_GATE_LAST_OUTPUT=""
TEST_GATE_LAST_OUTPUT=""
TRUTHSAYER_GATE_LAST_OUTPUT=""
CENTURION_LAST_CHECKS=""
CENTURION_LAST_LEVEL="standard"

_repo_config_value() {
    local repo_path="$1" key="$2"
    if [[ -f "${CONFIG_FILE:-}" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --arg repo "$repo_path" --arg key "$key" '.repos[$repo][$key] // empty' "$CONFIG_FILE"
    fi
}

_repo_timeout_seconds() {
    local repo_path="$1"
    local configured_timeout
    configured_timeout="$(_repo_config_value "$repo_path" timeout)"
    if [[ -n "$configured_timeout" ]] && is_integer "$configured_timeout"; then
        echo "$configured_timeout"
    else
        echo 300
    fi
}

run_lint_gate() {
    local repo_path="$1"
    local output_file lint_cmd=""
    local configured_lint_cmd=""
    local timeout_seconds
    local -a shell_files=()

    output_file="$(mktemp)"
    LINT_GATE_LAST_OUTPUT=""
    timeout_seconds="$(_repo_timeout_seconds "$repo_path")"
    configured_lint_cmd="$(_repo_config_value "$repo_path" lint_cmd)"

    if [[ -n "$configured_lint_cmd" ]]; then
        lint_cmd="$configured_lint_cmd"
        if ! (cd "$repo_path" && timeout "$timeout_seconds" bash -lc "$configured_lint_cmd") >"$output_file" 2>&1; then
            LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
            rm -f "$output_file"
            echo "Lint gate failed: $lint_cmd" >&2
            echo "$LINT_GATE_LAST_OUTPUT" >&2
            return 1
        fi
        rm -f "$output_file"
        echo "Lint gate passed: $lint_cmd"
        return 0
    fi

    # Go: prefer golangci-lint, fall back to go vet.
    if [[ -f "$repo_path/go.mod" ]]; then
        if command -v golangci-lint >/dev/null 2>&1; then
            lint_cmd="golangci-lint run"
            if ! (cd "$repo_path" && timeout "$timeout_seconds" golangci-lint run) >"$output_file" 2>&1; then
                LINT_GATE_LAST_OUTPUT="$(cat "$output_file")"
                rm -f "$output_file"
                echo "Lint gate failed: $lint_cmd" >&2
                echo "$LINT_GATE_LAST_OUTPUT" >&2
                return 1
            fi
        else
            lint_cmd="go vet ./..."
            if ! (cd "$repo_path" && timeout "$timeout_seconds" go vet ./...) >"$output_file" 2>&1; then
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
                if ! (cd "$repo_path" && timeout "$timeout_seconds" ./node_modules/.bin/eslint .) >"$output_file" 2>&1; then
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
                if ! (cd "$repo_path" && timeout "$timeout_seconds" npx --no-install eslint .) >"$output_file" 2>&1; then
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
        if ! (cd "$repo_path" && timeout "$timeout_seconds" shellcheck "${shell_files[@]}") >"$output_file" 2>&1; then
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

run_unit_test_gate() {
    local repo_path="$1"
    local timeout_seconds
    local configured_test_cmd=""
    local runner_label=""
    local output_file
    local -a test_cmd=()

    timeout_seconds="$(_repo_timeout_seconds "$repo_path")"
    configured_test_cmd="$(_repo_config_value "$repo_path" test_cmd)"

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

    output_file="$(mktemp)"
    if (cd "$repo_path" && timeout "$timeout_seconds" "${test_cmd[@]}") >"$output_file" 2>&1; then
        rm -f "$output_file"
        TEST_GATE_LAST_OUTPUT=""
        echo "Test gate passed: $runner_label"
        return 0
    fi

    local exit_code=$?
    TEST_GATE_LAST_OUTPUT="$(tail -n 50 "$output_file" || true)"
    rm -f "$output_file"
    echo "Test gate failed: $runner_label (exit $exit_code)" >&2
    [[ -n "$TEST_GATE_LAST_OUTPUT" ]] && echo "$TEST_GATE_LAST_OUTPUT" >&2
    return 1
}

run_truthsayer_gate() {
    local repo_path="$1"
    local timeout_seconds ts_output ts_bin

    TRUTHSAYER_GATE_LAST_OUTPUT=""
    timeout_seconds="$(_repo_timeout_seconds "$repo_path")"

    if [[ "${CENTURION_SKIP_TRUTHSAYER:-false}" == "true" ]]; then
        echo "Truthsayer gate skipped: CENTURION_SKIP_TRUTHSAYER=true"
        return 0
    fi

    if ! command -v truthsayer >/dev/null 2>&1 && [[ ! -x "$HOME/go/bin/truthsayer" ]]; then
        echo "Truthsayer gate skipped: binary not available"
        return 0
    fi

    ts_bin="${TRUTHSAYER_BIN:-${HOME}/go/bin/truthsayer}"
    [[ -x "$ts_bin" ]] || ts_bin="truthsayer"

    ts_output="$(timeout "$timeout_seconds" "$ts_bin" scan "$repo_path" --severity error 2>&1)" || {
        local ts_exit=$?
        TRUTHSAYER_GATE_LAST_OUTPUT="$ts_output"
        echo "Truthsayer gate failed (exit $ts_exit)" >&2
        echo "$ts_output" >&2
        return 1
    }

    echo "Truthsayer gate passed"
    return 0
}

run_quality_gate() {
    local repo_path="$1"
    local level="${2:-standard}"

    TEST_GATE_LAST_OUTPUT=""
    CENTURION_LAST_CHECKS=""
    CENTURION_LAST_LEVEL="$level"

    case "$level" in
        quick)
            CENTURION_LAST_CHECKS="lint"
            run_lint_gate "$repo_path" || {
                TEST_GATE_LAST_OUTPUT="Lint checks failed:
$LINT_GATE_LAST_OUTPUT"
                return 1
            }
            return 0
            ;;
        standard)
            CENTURION_LAST_CHECKS="lint,tests,truthsayer"
            run_lint_gate "$repo_path" || {
                TEST_GATE_LAST_OUTPUT="Lint checks failed:
$LINT_GATE_LAST_OUTPUT"
                return 1
            }
            run_unit_test_gate "$repo_path" || return 1
            run_truthsayer_gate "$repo_path" || {
                TEST_GATE_LAST_OUTPUT="Truthsayer checks failed:
$TRUTHSAYER_GATE_LAST_OUTPUT"
                return 1
            }
            return 0
            ;;
        deep)
            CENTURION_LAST_CHECKS="lint,tests,truthsayer,semantic-review"
            run_quality_gate "$repo_path" "standard" || return 1
            echo "Deep mode: mechanical checks passed"
            return 0
            ;;
        *)
            TEST_GATE_LAST_OUTPUT="Unknown quality level: $level"
            return 1
            ;;
    esac
}

# Backwards-compatible alias used by older scripts/tests.
run_test_gate() {
    local repo_path="$1"
    run_quality_gate "$repo_path" "standard"
}
