# shellcheck shell=bash
# common.sh — Shared utility functions for dispatch scripts
# Source this file; do not execute directly.

iso_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_now() {
    date -u +%s
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

status_is_terminal() {
    case "$1" in
        done|failed|timeout) return 0 ;;
        *) return 1 ;;
    esac
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: required command not found: $1" >&2
        exit 1
    fi
}

# Check available disk space in MB. Returns 0 if enough, 1 if not.
check_disk_space() {
    local path="$1" min_mb="${2:-500}"
    local avail_kb
    avail_kb="$(df -P "$path" 2>/dev/null | awk 'NR==2 {print $4}')" || avail_kb=0
    local avail_mb=$(( avail_kb / 1024 ))
    if (( avail_mb < min_mb )); then
        echo "Error: only ${avail_mb}MB free at $path (need ${min_mb}MB)" >&2
        return 1
    fi
    return 0
}

# Kill a tmux session safely, ignoring errors if already gone.
kill_tmux_session() {
    local socket="$1" session="$2"
    tmux -S "$socket" kill-session -t "$session" 2>/dev/null || true
}

# Check if a tmux session exists.
tmux_session_exists() {
    local socket="$1" session="$2"
    tmux -S "$socket" has-session -t "$session" 2>/dev/null
}

# List all tmux sessions on a socket. Returns empty string if none.
tmux_list_sessions() {
    local socket="$1"
    [[ -S "$socket" ]] || { echo ""; return 0; }
    tmux -S "$socket" list-sessions -F "#{session_name}" 2>/dev/null || echo ""
}

# Detect stale agent sessions: run records say "running" but tmux session is gone.
# Prints bead IDs of stale agents, one per line.
detect_stale_agents() {
    local runs_dir="$1" socket="$2"
    [[ -d "$runs_dir" ]] || return 0
    for run_file in "$runs_dir"/*.json; do
        [[ -f "$run_file" ]] || continue
        local status bead session
        status="$(jq -r '.status // empty' "$run_file" 2>/dev/null)" || continue
        [[ "$status" == "running" ]] || continue
        bead="$(jq -r '.bead // empty' "$run_file" 2>/dev/null)" || continue
        session="$(jq -r '.session_name // empty' "$run_file" 2>/dev/null)" || continue
        [[ -n "$session" ]] || continue
        if ! tmux_session_exists "$socket" "$session"; then
            echo "$bead"
        fi
    done
}
