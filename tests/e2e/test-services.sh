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

probe_http_any_path() {
    local name="$1"
    local port="$2"
    local body_file
    body_file="$(mktemp)"

    local path
    for path in / /health /healthz /status /api/health; do
        local code
        if code="$(curl -sS -m 5 -o "$body_file" -w '%{http_code}' "http://127.0.0.1:${port}${path}")"; then
            :
        else
            code="000"
        fi
        if [[ "$code" != "000" ]]; then
            pass "$name responds on :$port (path: $path, http: $code)"
            rm -f "$body_file"
            return 0
        fi
    done

    fail "$name did not respond on :$port"
    rm -f "$body_file"
    return 0
}

probe_http_html_root() {
    local name="$1"
    local port="$2"
    local body_file
    body_file="$(mktemp)"

    local code
    if code="$(curl -sS -m 5 -o "$body_file" -w '%{http_code}' "http://127.0.0.1:${port}/")"; then
        :
    else
        code="000"
    fi
    if [[ "$code" == "000" ]]; then
        fail "$name did not respond on :$port"
        rm -f "$body_file"
        return 0
    fi

    if grep -Eiq '<!doctype html|<html' "$body_file"; then
        pass "$name responds on :$port and serves HTML"
    else
        fail "$name responded on :$port but body is not HTML"
    fi

    rm -f "$body_file"
    return 0
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

echo "== Services Health E2E =="

probe_http_any_path "openclaw-gateway" "18500"
probe_http_html_root "athena-web" "9000"

if service_active "argus"; then
    pass "argus service is active"
elif pgrep -f "$HOME/argus/argus.sh" >/dev/null 2>&1; then
    pass "argus process is running (systemctl unavailable or inactive)"
else
    fail "argus service is not active"
fi

finish
