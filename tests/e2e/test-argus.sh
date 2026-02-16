#!/usr/bin/env bash
set -euo pipefail

if [[ -v ARGUS_HOME ]]; then
    ARGUS_HOME="${ARGUS_HOME:?ARGUS_HOME cannot be empty}"
else
    ARGUS_HOME="$HOME/argus"
fi

if [[ -v ARGUS_RECENT_SECONDS ]]; then
    RECENT_SECONDS="${ARGUS_RECENT_SECONDS:?ARGUS_RECENT_SECONDS cannot be empty}"
else
    RECENT_SECONDS="86400"
fi

if [[ ! "$RECENT_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "Error: ARGUS_RECENT_SECONDS must be a positive integer (got: $RECENT_SECONDS)" >&2
    exit 1
fi

PASSED=0
FAILED=0
STATUS="PASS"
DETAIL=""

ARGUS_ACTIVE=0

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

service_active() {
    local service_name="$1"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$service_name"; then
            return 0
        fi
        if systemctl --user is-active --quiet "$service_name"; then
            return 0
        fi
    fi
    return 1
}

check_recent_file() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    local modified_ts
    if modified_ts="$(stat -c %Y "$file_path")"; then
        :
    else
        modified_ts="0"
    fi
    local now_ts
    now_ts="$(date +%s)"
    local age=$((now_ts - modified_ts))
    (( age >= 0 && age <= RECENT_SECONDS ))
}

echo "== Argus Health E2E =="

if service_active "argus"; then
    ARGUS_ACTIVE=1
    pass "argus service is active"
elif pgrep -f "${ARGUS_HOME}/argus.sh" >/dev/null 2>&1; then
    ARGUS_ACTIVE=1
    pass "argus process is running (fallback check)"
else
    fail "argus service is not active"
fi

if [[ "$ARGUS_ACTIVE" -eq 1 ]]; then
    pass "argus.sh --once skipped because service is active"
else
    ARGUS_CMD=""
    if command -v argus.sh >/dev/null 2>&1; then
        ARGUS_CMD="$(command -v argus.sh)"
    elif [[ -x "${ARGUS_HOME}/argus.sh" ]]; then
        ARGUS_CMD="${ARGUS_HOME}/argus.sh"
    fi

    if [[ -z "$ARGUS_CMD" ]]; then
        fail "argus.sh command not found for --once health check"
    else
        if [[ -f "${ARGUS_HOME}/argus.env" ]]; then
            if bash -lc "set -euo pipefail; source '${ARGUS_HOME}/argus.env'; '${ARGUS_CMD}' --once" >/dev/null 2>&1; then
                pass "argus.sh --once ran successfully"
            else
                fail "argus.sh --once returned a non-zero exit code"
            fi
        else
            if "$ARGUS_CMD" --once >/dev/null 2>&1; then
                pass "argus.sh --once ran successfully"
            else
                fail "argus.sh --once returned a non-zero exit code"
            fi
        fi
    fi
fi

ARGUS_LOG="${ARGUS_HOME}/logs/argus.log"
if check_recent_file "$ARGUS_LOG"; then
    pass "argus logs exist and are recent (${ARGUS_LOG})"
else
    fail "argus log missing or older than ${RECENT_SECONDS}s (${ARGUS_LOG})"
fi

finish
