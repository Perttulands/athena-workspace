#!/usr/bin/env bash
# E2E test helpers — single assertion library for all tests
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

PASSED_COUNT=0
FAILED_COUNT=0

begin() {
    echo -e "${YELLOW}▶ TEST: $1${NC}"
}

pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
}

fail() {
    echo -e "${RED}✗ FAIL: $1 — $2${NC}" >&2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    exit 1
}

skip() {
    echo -e "${YELLOW}⊘ SKIP: $1${NC}"
    exit 0
}

assert_not_empty() {
    local val="$1" msg="$2"
    [[ -n "$val" ]] || fail "$msg" "value was empty"
}

assert_equals() {
    local expected="$1" actual="$2" msg="$3"
    [[ "$expected" == "$actual" ]] || fail "$msg" "expected '$expected', got '$actual'"
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$msg" "expected to contain '$needle'"
}

assert_file_exists() {
    local path="$1" msg="$2"
    [[ -f "$path" ]] || fail "$msg" "file not found: $path"
}

assert_file_not_exists() {
    local path="$1" msg="$2"
    [[ ! -f "$path" ]] || fail "$msg" "file should not exist: $path"
}

assert_exit_zero() {
    local msg="$1"; shift
    "$@" || fail "$msg" "command exited $?"
}

assert_json_field() {
    local json="$1" field="$2" expected="$3" msg="$4"
    local actual
    actual="$(echo "$json" | jq -r "$field")"
    [[ "$actual" == "$expected" ]] || fail "$msg" "expected $field='$expected', got '$actual'"
}

assert_json_file_field() {
    local file="$1" field="$2" expected="$3" msg="$4"
    [[ -f "$file" ]] || fail "$msg" "file not found: $file"
    local actual
    actual="$(jq -r "$field" "$file" 2>/dev/null)" || fail "$msg" "invalid JSON in $file"
    [[ "$actual" == "$expected" ]] || fail "$msg" "expected $field='$expected', got '$actual'"
}

assert_json_valid() {
    local file="$1" msg="$2"
    jq -e . "$file" >/dev/null 2>&1 || fail "$msg" "invalid JSON: $file"
}

assert_tmux_session_exists() {
    local socket="$1" session="$2" msg="$3"
    tmux -S "$socket" has-session -t "$session" 2>/dev/null || fail "$msg" "session not found: $session"
}

# Utilities

generate_test_id() {
    local prefix="${1:-test}"
    echo "${prefix}-$(date +%s)-$$-$RANDOM"
}

wait_for_terminal_status() {
    local run_file="$1" timeout_seconds="${2:-60}" elapsed=0
    while (( elapsed < timeout_seconds )); do
        if [[ -f "$run_file" ]]; then
            local status
            status="$(jq -r '.status // empty' "$run_file" 2>/dev/null)" || status=""
            case "$status" in done|failed|timeout) return 0 ;; esac
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

cleanup_test_bead() {
    local bead_id="$1" workspace="$2" socket="${3:-/tmp/openclaw-coding-agents.sock}"
    tmux -S "$socket" kill-session -t "agent-$bead_id" 2>/dev/null || true
    rm -f "$workspace/state/runs/$bead_id.json" \
          "$workspace/state/results/$bead_id.json" \
          "$workspace/state/results/${bead_id}-verify.json" \
          "$workspace/state/watch/$bead_id".*
    bd delete "$bead_id" --force 2>/dev/null || true
}
