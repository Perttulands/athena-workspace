#!/usr/bin/env bash
# dispatch.sh — Dispatch coding agents to a shared branch
#
# Usage: dispatch.sh <bead-id> <repo-path> <agent-type> <prompt> [--branch <name>]
#   agent-type: claude:opus | claude:sonnet | codex | codex:gpt-5.3-codex
#
# Agents coordinate via shared run context and branch discipline.
# No worktrees. No per-agent branches.
# Multiple agents can work the same repo and branch simultaneously.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/record.sh"

# ── Arguments ────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 <bead-id> <repo-path> <agent-type> <prompt> [--branch <name>] [--force]" >&2
}

(( $# >= 4 )) || { usage; exit 1; }

BEAD_ID="$1"
REPO_PATH="$(cd "$2" && pwd)"
AGENT_TYPE_RAW="$3"
PROMPT="$4"
shift 4

BRANCH=""
FORCE_DISPATCH="${DISPATCH_FORCE:-false}"
TEMPLATE_NAME="custom"

while (( $# > 0 )); do
    case "$1" in
        --branch) BRANCH="$2"; shift 2 ;;
        --force)  FORCE_DISPATCH="true"; shift ;;
        *)        TEMPLATE_NAME="$1"; shift ;;
    esac
done

AGENT_TYPE="${AGENT_TYPE_RAW%%:*}"
MODEL_OVERRIDE=""
if [[ "$AGENT_TYPE_RAW" == *:* ]]; then
    MODEL_OVERRIDE="${AGENT_TYPE_RAW#*:}"
    [[ -n "$MODEL_OVERRIDE" ]] || { echo "Error: empty model after colon in '$AGENT_TYPE_RAW'" >&2; exit 1; }
fi

# ── Configuration ────────────────────────────────────────────────────────────

TMUX_SOCKET="${DISPATCH_TMUX_SOCKET:-/tmp/openclaw-coding-agents.sock}"
MAX_RETRIES="${DISPATCH_MAX_RETRIES:-2}"
WATCH_INTERVAL_SECONDS="${DISPATCH_WATCH_INTERVAL:-20}"
WATCH_TIMEOUT_SECONDS="${DISPATCH_WATCH_TIMEOUT:-3600}"

for var in MAX_RETRIES WATCH_INTERVAL_SECONDS WATCH_TIMEOUT_SECONDS; do
    val="${!var}"
    if ! is_integer "$val" || (( val < 1 )); then
        echo "Error: $var must be a positive integer (got '$val')" >&2
        exit 1
    fi
done

STATE_DIR="$WORKSPACE_ROOT/state"
RUNS_DIR="$STATE_DIR/runs"
RESULTS_DIR="$STATE_DIR/results"
WATCH_DIR="$STATE_DIR/watch"
TRUTHSAYER_BIN="${TRUTHSAYER_BIN:-$HOME/truthsayer/truthsayer}"
TRUTHSAYER_LOG_DIR="$STATE_DIR/truthsayer"
SESSION_NAME="agent-$BEAD_ID"
RUN_RECORD="$RUNS_DIR/$BEAD_ID.json"
RESULT_RECORD="$RESULTS_DIR/$BEAD_ID.json"
STATUS_FILE="$WATCH_DIR/$BEAD_ID.status.json"
PROMPT_FILE="$WATCH_DIR/$BEAD_ID.prompt.txt"
RUNNER_SCRIPT="$WATCH_DIR/$BEAD_ID.runner.sh"
TRUTHSAYER_PID=""

mkdir -p "$RUNS_DIR" "$RESULTS_DIR" "$WATCH_DIR" "$TRUTHSAYER_LOG_DIR"

# ── Prerequisites ────────────────────────────────────────────────────────────

require_cmd jq
require_cmd tmux
require_cmd sha256sum
if [[ -x "$SCRIPT_DIR/lint-no-hidden-workspace.sh" ]]; then
    "$SCRIPT_DIR/lint-no-hidden-workspace.sh"
fi

# Disk space check — abort early if disk is nearly full
check_disk_space "$WORKSPACE_ROOT" 200 || {
    echo "Error: insufficient disk space to dispatch agent for bead '$BEAD_ID'" >&2
    exit 1
}
check_disk_space "$REPO_PATH" 200 || {
    echo "Error: insufficient disk space at repo '$REPO_PATH'" >&2
    exit 1
}

# ── Build agent command ──────────────────────────────────────────────────────

if [[ -n "$MODEL_OVERRIDE" ]]; then
    AGENT_MODEL="$MODEL_OVERRIDE"
elif [[ "$AGENT_TYPE" == "claude" && -n "${DISPATCH_CLAUDE_MODEL:-}" ]]; then
    AGENT_MODEL="$DISPATCH_CLAUDE_MODEL"
elif [[ "$AGENT_TYPE" == "codex" && -n "${DISPATCH_CODEX_MODEL:-}" ]]; then
    AGENT_MODEL="$DISPATCH_CODEX_MODEL"
else
    AGENT_MODEL=""
fi

build_agent_cmd "$AGENT_TYPE" "$AGENT_MODEL" || exit 1

[[ "$AGENT_TYPE" == "codex" && ! -d "$REPO_PATH/.git" ]] && AGENT_CMD+=(--skip-git-repo-check)
# Codex reads prompt from stdin via '-'
[[ "$AGENT_TYPE" == "codex" ]] && AGENT_CMD+=(-)

# ── Helpers ──────────────────────────────────────────────────────────────────

session_exists() { tmux_session_exists "$TMUX_SOCKET" "$SESSION_NAME"; }

json_field() {
    local file="$1" filter="$2" default="$3"
    [[ -f "$file" ]] && jq -r "$filter" "$file" 2>/dev/null || echo "$default"
}

count_truthsayer_findings() {
    [[ -f "$1" ]] && awk '/^(ERROR|WARNING)/ {c++} END {print c+0}' "$1" || echo 0
}

stop_truthsayer() {
    [[ -n "$TRUTHSAYER_PID" ]] || return 0
    kill "$TRUTHSAYER_PID" 2>/dev/null || true
    wait "$TRUTHSAYER_PID" 2>/dev/null || true
    TRUTHSAYER_PID=""
}

cleanup_runtime() {
    rm -f "$PROMPT_FILE" "$RUNNER_SCRIPT"
    stop_truthsayer
}

# Build coordination context: other active agents on this repo
build_coordination_context() {
    local active_beads=""
    for run_file in "$RUNS_DIR"/*.json; do
        [[ -f "$run_file" ]] || continue
        local bead status repo
        bead="$(jq -r '.bead // empty' "$run_file" 2>/dev/null)" || continue
        [[ "$bead" == "$BEAD_ID" ]] && continue
        status="$(jq -r '.status // empty' "$run_file" 2>/dev/null)" || continue
        [[ "$status" == "running" ]] || continue
        repo="$(jq -r '.repo // empty' "$run_file" 2>/dev/null)" || continue
        [[ "$repo" == "$REPO_PATH" ]] || continue
        local prompt_short
        prompt_short="$(jq -r '.prompt // empty' "$run_file" 2>/dev/null | head -c 200)" || prompt_short=""
        active_beads+="- Bead $bead ($AGENT_TYPE): $prompt_short
"
    done
    echo "$active_beads"
}

append_memory() {
    local status="$1" duration="$2" reason="$3" will_retry="$4"
    local file
    file="$WORKSPACE_ROOT/memory/$(date -u +%Y-%m-%d).md"
    mkdir -p "$(dirname "$file")"
    [[ -f "$file" ]] || printf '# %s\n\n' "$(date -u +%Y-%m-%d)" > "$file"
    printf -- '- Bead `%s`: agent=%s model=%s attempt=%s/%s status=%s duration=%ss reason=%s\n' \
        "$BEAD_ID" "$AGENT_TYPE" "$MODEL" "$ATTEMPT" "$MAX_RETRIES" "$status" "$duration" "$reason" >> "$file"
}

wake_athena() {
    local status="$1" duration="$2" reason="$3"
    local ts_msg="" ts_log="$TRUTHSAYER_LOG_DIR/$BEAD_ID.log"
    if [[ -f "$ts_log" ]]; then
        local n
        n="$(count_truthsayer_findings "$ts_log")"
        (( n > 0 )) && ts_msg=", truthsayer: ${n} issues"
    fi
    local script="$SCRIPT_DIR/wake-gateway.sh"
    if [[ -x "$script" ]]; then
        "$script" "Agent $BEAD_ID $status (${duration}s, $AGENT_TYPE/$MODEL, attempt $ATTEMPT/$MAX_RETRIES, reason: $reason${ts_msg}). Check state/results/$BEAD_ID.json and message Perttu with the result summary." || true
    fi
}

# ── Completion detection ─────────────────────────────────────────────────────

DETECTED_STATUS="" DETECTED_EXIT_CODE="" DETECTED_REASON="" DETECTED_FINISHED_AT=""

set_detection() { DETECTED_STATUS="$1"; DETECTED_EXIT_CODE="$2"; DETECTED_REASON="$3"; DETECTED_FINISHED_AT="$4"; }

detect_completion() {
    # 1. Status file
    if [[ -f "$STATUS_FILE" ]] && jq -e '.exit_code and .finished_at' "$STATUS_FILE" &>/dev/null; then
        local ec fa
        ec="$(jq -r '.exit_code' "$STATUS_FILE")"
        fa="$(jq -r '.finished_at' "$STATUS_FILE")"
        if [[ -n "${STARTED_EPOCH:-}" ]]; then
            local fe
            fe="$(date -d "$fa" +%s 2>/dev/null)" || fe=0
            (( fe < STARTED_EPOCH )) && return 1
        fi
        if [[ "$ec" == "0" ]]; then
            set_detection "done" "0" "status-file" "$fa"
        else
            set_detection "failed" "$ec" "status-file" "$fa"
        fi
        return 0
    fi

    # 2. Pane inspection
    if session_exists; then
        local pane
        pane="$(tmux -S "$TMUX_SOCKET" capture-pane -t "$SESSION_NAME" -p -S -300 2>/dev/null)" || pane=""

        local ec
        ec="$(printf '%s\n' "$pane" | sed -n 's/^OPENCLAW_EXIT_CODE:\([0-9]\+\)$/\1/p' | tail -1)"
        if [[ -n "$ec" ]]; then
            local fa
            fa="$(printf '%s\n' "$pane" | sed -n 's/^OPENCLAW_FINISHED_AT:\(.*\)$/\1/p' | tail -1)"
            [[ -z "$fa" ]] && fa="$(iso_now)"
            if [[ "$ec" == "0" ]]; then
                set_detection "done" "0" "pane-marker" "$fa"
            else
                set_detection "failed" "$ec" "pane-marker" "$fa"
            fi
            return 0
        fi

        local last; last="$(printf '%s\n' "$pane" | awk 'NF {line=$0} END {print line}')"
        if [[ -n "$last" ]] && [[ "$last" =~ [#$%][[:space:]]?$ ]]; then
            set_detection "done" "0" "prompt-heuristic" "$(iso_now)"
            return 0
        fi
        return 1
    fi

    # 3. Session gone
    if [[ -f "$STATUS_FILE" ]] && jq -e '.exit_code and .finished_at' "$STATUS_FILE" &>/dev/null; then
        local ec fa
        ec="$(jq -r '.exit_code' "$STATUS_FILE")"
        fa="$(jq -r '.finished_at' "$STATUS_FILE")"
        if [[ "$ec" == "0" ]]; then
            set_detection "done" "0" "status-file" "$fa"
        else
            set_detection "failed" "$ec" "status-file" "$fa"
        fi
        return 0
    fi
    set_detection "failed" "127" "session-exited-without-markers" "$(iso_now)"
    return 0
}

# ── Complete run ─────────────────────────────────────────────────────────────

complete_run() {
    local status="$1" exit_code="$2" reason="$3" finished_at="${4:-$(iso_now)}"
    local now duration will_retry="false" output_summary="" failure_reason=""

    now="$(epoch_now)"
    duration=$(( now - STARTED_EPOCH ))
    (( duration < 0 )) && duration=0
    [[ "$status" != "done" && "$ATTEMPT" -lt "$MAX_RETRIES" ]] && will_retry="true"

    if session_exists; then
        output_summary="$(tmux -S "$TMUX_SOCKET" capture-pane -t "$SESSION_NAME" -p -S -500 2>/dev/null | tail -c 500)" || output_summary=""
    fi
    [[ "$status" == "failed" || "$status" == "timeout" ]] && failure_reason="$reason"

    stop_truthsayer

    # Verification
    local verification_json="null" verification_overall="unknown"
    if [[ -x "$WORKSPACE_ROOT/scripts/verify.sh" ]]; then
        local vout
        if vout="$("$WORKSPACE_ROOT/scripts/verify.sh" "$REPO_PATH" "$BEAD_ID")"; then
            verification_json="$(printf '%s' "$vout" | jq '.checks' 2>/dev/null)" || verification_json="null"
            verification_overall="$(printf '%s' "$vout" | jq -r '.overall // "unknown"' 2>/dev/null)" || verification_overall="unknown"
        else
            verification_overall="fail"
        fi
    fi

    # Write records
    write_run_record "$status" "$finished_at" "$duration" "$exit_code" "$output_summary" "$failure_reason" "$verification_json"
    write_result_record "$status" "$reason" "$finished_at" "$duration" "$exit_code" "$will_retry" "$output_summary" "$verification_json"

    # Advisory validation
    if [[ -x "$WORKSPACE_ROOT/scripts/validate-state.sh" ]]; then
        "$WORKSPACE_ROOT/scripts/validate-state.sh" --runs "$RUN_RECORD" --results "$RESULT_RECORD" 2>/dev/null || true
    fi

    # Cleanup
    if session_exists; then
        tmux -S "$TMUX_SOCKET" kill-session -t "$SESSION_NAME" 2>/dev/null || true
    fi
    cleanup_runtime
    append_memory "$status" "$duration" "$reason" "$will_retry"
    wake_athena "$status" "$duration" "$reason"
}

# ── Background watcher ───────────────────────────────────────────────────────

launch_watcher() {
    (
        set -euo pipefail

        # Handle signals gracefully — mark the agent as failed if watcher is killed
        _watcher_interrupted=false
        _watcher_signal_handler() {
            _watcher_interrupted=true
        }
        trap '_watcher_signal_handler' SIGTERM SIGINT SIGHUP

        local deadline=$((STARTED_EPOCH + WATCH_TIMEOUT_SECONDS))
        local consecutive_errors=0
        local max_errors=10

        while true; do
            if [[ "$_watcher_interrupted" == "true" ]]; then
                complete_run "failed" "130" "watcher-signal-interrupted" "$(iso_now)"
                exit 1
            fi

            if detect_completion; then
                complete_run "$DETECTED_STATUS" "$DETECTED_EXIT_CODE" "$DETECTED_REASON" "$DETECTED_FINISHED_AT"
                exit 0
            fi

            if (( $(epoch_now) >= deadline )); then
                # Kill the tmux session on timeout — don't leave orphans
                kill_tmux_session "$TMUX_SOCKET" "$SESSION_NAME"
                complete_run "timeout" "124" "watch-timeout-${WATCH_TIMEOUT_SECONDS}s" "$(iso_now)"
                exit 0
            fi

            # Detect disk space issues during execution
            if ! check_disk_space "$WORKSPACE_ROOT" 100 2>/dev/null; then
                echo "Warning: disk space critically low during agent run $BEAD_ID" >&2
                kill_tmux_session "$TMUX_SOCKET" "$SESSION_NAME"
                complete_run "failed" "1" "disk-space-exhausted" "$(iso_now)"
                exit 1
            fi

            sleep "$WATCH_INTERVAL_SECONDS"
        done
    ) >/dev/null 2>&1 &
}

# ── Runner script ────────────────────────────────────────────────────────────

create_runner_script() {
    local cmd_literal
    printf -v cmd_literal '%q ' "${AGENT_CMD[@]}"

    cat > "$RUNNER_SCRIPT" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
STATUS_FILE=$(printf '%q' "$STATUS_FILE")
PROMPT_FILE=$(printf '%q' "$PROMPT_FILE")
BEAD_ID=$(printf '%q' "$BEAD_ID")
AGENT_CMD=($cmd_literal)

_emit_done=false
emit_status() {
    # Guard against double-emit (signal + EXIT trap)
    [[ "\$_emit_done" == "true" ]] && return 0
    _emit_done=true

    local ec="\$1" ts tmp
    # Commit any uncommitted work
    if git status --porcelain 2>/dev/null | grep -q .; then
        git add -A 2>/dev/null || true
        git commit -m "agent work: bead \$BEAD_ID" --no-verify 2>/dev/null || true
    fi
    ts="\$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    tmp="\${STATUS_FILE}.tmp"
    if jq -cn --arg bead "\$BEAD_ID" --arg finished_at "\$ts" --argjson exit_code "\$ec" \
        '{bead:\$bead, finished_at:\$finished_at, exit_code:\$exit_code}' > "\$tmp" 2>/dev/null; then
        mv "\$tmp" "\$STATUS_FILE"
    else
        # Fallback: write without jq in case jq is unavailable
        printf '{"bead":"%s","finished_at":"%s","exit_code":%s}\n' "\$BEAD_ID" "\$ts" "\$ec" > "\$STATUS_FILE"
        rm -f "\$tmp" 2>/dev/null || true
    fi
    echo "OPENCLAW_EXIT_CODE:\$ec"
    echo "OPENCLAW_FINISHED_AT:\$ts"
}
trap 'emit_status "\$?"' EXIT
trap 'emit_status "130"' SIGTERM SIGINT SIGHUP
"\${AGENT_CMD[@]}" < "\$PROMPT_FILE"
RUNNER
    chmod +x "$RUNNER_SCRIPT"
}

# ── Build full prompt with coordination context ──────────────────────────────

build_full_prompt() {
    local coordination
    coordination="$(build_coordination_context)"

    local coord_section=""
    if [[ -n "$coordination" ]]; then
        coord_section="

## Other Active Agents (same repo)
These agents are currently working on this repo. Coordinate to avoid overlap.
$coordination
"
    fi

    cat <<PROMPT
$PROMPT
$coord_section
## Coordination Instructions
- You are agent for bead $BEAD_ID working on branch: $(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
- Check the active-agent list above and avoid overlapping file edits
- Announce intended scope in your first response before making edits
- Pull before committing: git pull --rebase
- Commit frequently with descriptive messages referencing bead $BEAD_ID
- When done, provide a clear completion summary with test results and commit SHA
PROMPT
}

# ── Main ─────────────────────────────────────────────────────────────────────

# Preflight
[[ -x "$WORKSPACE_ROOT/scripts/agent-preflight.sh" ]] && "$WORKSPACE_ROOT/scripts/agent-preflight.sh" "$AGENT_TYPE" "$REPO_PATH"
if [[ "${DISPATCH_ENFORCE_PRD_LINT:-true}" == "true" ]] && [[ -x "$WORKSPACE_ROOT/scripts/prd-lint.sh" ]]; then
    prd_lint_report="$(mktemp)"
    if ! "$WORKSPACE_ROOT/scripts/prd-lint.sh" > "$prd_lint_report"; then
        echo "Error: PRD governance check failed. Dispatch blocked." >&2
        cat "$prd_lint_report" >&2
        rm -f "$prd_lint_report"
        exit 1
    fi
    rm -f "$prd_lint_report"
fi

# Branch management
if [[ -n "$BRANCH" ]] && git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
    if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
        git -C "$REPO_PATH" checkout "$BRANCH" 2>/dev/null || true
    else
        git -C "$REPO_PATH" checkout -b "$BRANCH" 2>/dev/null || true
    fi
fi

# Handle existing session
if session_exists; then
    result_status="$(json_field "$RESULT_RECORD" '.status // ""' "")"
    run_status="$(json_field "$RUN_RECORD" '.status // ""' "")"
    if status_is_terminal "$result_status" || status_is_terminal "$run_status"; then
        echo "Cleaning up stale tmux session '$SESSION_NAME' (status: result=$result_status, run=$run_status)"
        kill_tmux_session "$TMUX_SOCKET" "$SESSION_NAME"
    elif [[ "$FORCE_DISPATCH" == "true" ]]; then
        echo "Force-killing existing session '$SESSION_NAME'"
        kill_tmux_session "$TMUX_SOCKET" "$SESSION_NAME"
    else
        echo "Error: tmux session '$SESSION_NAME' already exists and appears active" >&2
        echo "  Run status: $run_status, Result status: $result_status" >&2
        echo "  Use --force to override, or check: tmux -S $TMUX_SOCKET attach -t $SESSION_NAME" >&2
        exit 1
    fi
fi

# Clean up stale status file from previous runs
if [[ -f "$STATUS_FILE" ]]; then
    _stale_finished="$(jq -r '.finished_at // empty' "$STATUS_FILE" 2>/dev/null)" || _stale_finished=""
    if [[ -n "$_stale_finished" ]]; then
        rm -f "$STATUS_FILE"
    fi
    unset _stale_finished
fi

# Determine attempt
prev_attempt="$(json_field "$RUN_RECORD" '.attempt // 0' "0")"
is_integer "$prev_attempt" || prev_attempt=0
ATTEMPT=$((prev_attempt + 1))

if (( ATTEMPT > MAX_RETRIES )); then
    ATTEMPT="$MAX_RETRIES"
    STARTED_AT="$(iso_now)"; STARTED_EPOCH="$(epoch_now)"
    PROMPT_TRUNCATED="${PROMPT:0:200}"
    PROMPT_HASH="$(printf '%s' "$PROMPT" | sha256sum | awk '{print $1}')"
    write_run_record "failed" "$STARTED_AT" "0" "1"
    write_result_record "failed" "max-retries-reached" "$STARTED_AT" "0" "1" "false"
    append_memory "failed" "0" "max-retries-reached" "false"
    wake_athena "failed" "0" "max-retries-reached"
    echo "Error: max retries reached for bead '$BEAD_ID' ($MAX_RETRIES)" >&2
    exit 1
fi

# Initialize
STARTED_AT="$(iso_now)"; STARTED_EPOCH="$(epoch_now)"
FULL_PROMPT="$(build_full_prompt)"
PROMPT_TRUNCATED="${PROMPT:0:200}"
PROMPT_HASH="$(printf '%s' "$PROMPT" | sha256sum | awk '{print $1}')"

printf '%s' "$FULL_PROMPT" > "$PROMPT_FILE"
create_runner_script

write_run_record "running" "" "" ""
write_result_record "running" "dispatched" "" "" "" "false"

echo "Starting agent session: $SESSION_NAME"
echo "Agent: $AGENT_TYPE | Model: $MODEL"
echo "Repo: $REPO_PATH"
echo "Branch: $(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')"
echo "Attempt: $ATTEMPT/$MAX_RETRIES"

# Truthsayer
if [[ -x "$TRUTHSAYER_BIN" ]]; then
    "$TRUTHSAYER_BIN" watch "$REPO_PATH" > "$TRUTHSAYER_LOG_DIR/$BEAD_ID.log" 2>&1 &
    TRUTHSAYER_PID=$!
fi

# Launch
if ! tmux -S "$TMUX_SOCKET" new-session -d -s "$SESSION_NAME" -c "$REPO_PATH" "bash '$RUNNER_SCRIPT'; exec bash"; then
    complete_run "failed" "1" "tmux-launch-failed" "$(iso_now)"
    echo "Error: failed to create tmux session '$SESSION_NAME'" >&2
    echo "  Socket: $TMUX_SOCKET" >&2
    echo "  Runner: $RUNNER_SCRIPT" >&2
    echo "  Repo: $REPO_PATH" >&2
    echo "  Check: tmux -S $TMUX_SOCKET list-sessions" >&2
    exit 1
fi

launch_watcher
echo "Agent dispatched. Background watcher PID: $!"
echo "To attach: tmux -S $TMUX_SOCKET attach -t $SESSION_NAME"
