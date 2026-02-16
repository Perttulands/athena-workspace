#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

finish() {
    local total=$((PASSED + FAILED))
    if [[ $FAILED -gt 0 ]]; then
        STATUS="FAIL"
    fi
    echo "E2E_RESULT|$STATUS|$PASSED|$total|$DETAIL"
    if [[ "$STATUS" == "FAIL" ]]; then
        exit 1
    fi
}

echo "== Workspace Integrity E2E =="

CORE_FILES=(
    "$WORKSPACE_ROOT/AGENTS.md"
    "$WORKSPACE_ROOT/TOOLS.md"
    "$WORKSPACE_ROOT/SOUL.md"
    "$WORKSPACE_ROOT/USER.md"
    "$WORKSPACE_ROOT/MEMORY.md"
)

missing_core=()
for file in "${CORE_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_core+=("$file")
    fi
done
if [[ ${#missing_core[@]} -eq 0 ]]; then
    pass "Core workspace files exist (AGENTS.md, TOOLS.md, SOUL.md, USER.md, MEMORY.md)"
else
    fail "Missing core files: ${missing_core[*]}"
fi

if [[ -f "$WORKSPACE_ROOT/skills/coding-agents/SKILL.md" ]]; then
    pass "skills/coding-agents/SKILL.md exists"
else
    fail "skills/coding-agents/SKILL.md is missing"
fi

if [[ -x "$WORKSPACE_ROOT/scripts/dispatch.sh" ]]; then
    pass "scripts/dispatch.sh is executable"
else
    fail "scripts/dispatch.sh missing or not executable"
fi

if [[ -d "$WORKSPACE_ROOT/state/runs" ]]; then
    pass "state/runs exists"
else
    fail "state/runs is missing"
fi

if [[ -d "$WORKSPACE_ROOT/state/results" ]]; then
    pass "state/results exists"
else
    fail "state/results is missing"
fi

if [[ -d "$WORKSPACE_ROOT/state/watch" ]]; then
    pass "state/watch exists"
else
    fail "state/watch is missing"
fi

finish
