# shellcheck shell=bash
# centurion-wake.sh — Shared wake notification helper for centurion scripts
# Source this file; do not execute directly.

notify_wake_gateway() {
    local message="$1"

    if [[ ! -x "$WAKE_GATEWAY_BIN" ]]; then
        echo "Warning: wake-gateway script unavailable at $WAKE_GATEWAY_BIN" >&2
        return 0
    fi

    if ! "$WAKE_GATEWAY_BIN" "$message" >/dev/null 2>&1; then
        echo "Warning: wake-gateway notification failed: $message" >&2
    fi
}
