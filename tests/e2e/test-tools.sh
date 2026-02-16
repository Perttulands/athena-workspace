#!/usr/bin/env bash
set -euo pipefail

PASSED=0
FAILED=0
STATUS="PASS"
DETAIL=""

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}

run_quick_check() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 10 "$@" >/dev/null 2>&1
    else
        "$@" >/dev/null 2>&1
    fi
}

check_tool() {
    local tool="$1"
    local -a cmd

    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "$tool not found in PATH"
        return
    fi

    case "$tool" in
        br) cmd=(br --version) ;;
        codex) cmd=(codex --version) ;;
        claude) cmd=(claude --version) ;;
        gh) cmd=(gh --version) ;;
        cass) cmd=(cass --help) ;;
        ntm) cmd=(ntm --help) ;;
        ubs) cmd=(ubs --help) ;;
        dcg) cmd=(dcg --help) ;;
        rtk) cmd=(rtk --help) ;;
        tailscale) cmd=(tailscale version) ;;
        *) cmd=("$tool" --help) ;;
    esac

    if run_quick_check "${cmd[@]}"; then
        pass "$tool is installed and responds"
    else
        fail "$tool exists but did not respond to help/version"
    fi
}

finish() {
    local total=$((PASSED + FAILED))
    if [[ $FAILED -gt 0 ]]; then
        STATUS="WARN"
        DETAIL="missing-or-unresponsive=$FAILED"
    fi
    echo "E2E_RESULT|$STATUS|$PASSED|$total|$DETAIL"
    exit 0
}

echo "== Tool Availability E2E =="

TOOLS=(br codex claude gh cass ntm ubs dcg rtk tailscale)
for tool in "${TOOLS[@]}"; do
    check_tool "$tool"
done

finish
