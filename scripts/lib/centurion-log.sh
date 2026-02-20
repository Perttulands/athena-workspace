# shellcheck shell=bash
# centurion-log.sh — Structured logging for Centurion scripts
# Source this file; do not execute directly.

CENTURION_LOG_LEVEL="info"
CENTURION_LOG_QUIET="false"

centurion_log_init() {
    local verbose="${1:-false}" quiet="${2:-false}"
    CENTURION_LOG_LEVEL="info"
    CENTURION_LOG_QUIET="false"

    if [[ "$verbose" == "true" ]]; then
        CENTURION_LOG_LEVEL="debug"
    fi
    if [[ "$quiet" == "true" ]]; then
        CENTURION_LOG_QUIET="true"
    fi
}

_centurion_log_should_emit() {
    local level="$1"

    if [[ "$CENTURION_LOG_QUIET" == "true" && "$level" != "error" && "$level" != "warn" ]]; then
        return 1
    fi

    case "$CENTURION_LOG_LEVEL:$level" in
        debug:debug|debug:info|debug:warn|debug:error) return 0 ;;
        info:info|info:warn|info:error) return 0 ;;
        info:debug) return 1 ;;
        *) return 0 ;;
    esac
}

_centurion_log() {
    local level="$1" message="$2"
    _centurion_log_should_emit "$level" || return 0

    local ts
    ts="$(iso_now)"
    local prefix="[${level^^}]"

    if [[ "$level" == "error" || "$level" == "warn" ]]; then
        printf '%s %s %s\n' "$ts" "$prefix" "$message" >&2
    else
        printf '%s %s %s\n' "$ts" "$prefix" "$message"
    fi
}

log_debug() { _centurion_log "debug" "$*"; }
log_info() { _centurion_log "info" "$*"; }
log_warn() { _centurion_log "warn" "$*"; }
log_error() { _centurion_log "error" "$*"; }
