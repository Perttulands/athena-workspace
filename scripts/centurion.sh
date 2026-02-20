#!/usr/bin/env bash
# centurion.sh — Merge a branch to main with quality-gated checks
#
# Usage:
#   centurion.sh merge [--level quick|standard|deep] [--dry-run] [--verbose|--quiet] <branch> <repo-path>
#                                           Merge branch into main (quality-gated)
#   centurion.sh status [--verbose|--quiet] [repo-path]  Show branch/merge status
#   centurion.sh history [--limit N] [--verbose|--quiet] Show recent centurion run history
#   centurion.sh check [--level quick|standard|deep] [--verbose|--quiet] [repo-path]
#                                           Run quality checks without merging (pre-commit friendly)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WAKE_GATEWAY_BIN="${CENTURION_WAKE_BIN:-$SCRIPT_DIR/wake-gateway.sh}"
CENTURION_RESULTS_DIR="${CENTURION_RESULTS_DIR:-$WORKSPACE_ROOT/state/results}"
CENTURION_HISTORY_FILE="${CENTURION_HISTORY_FILE:-$WORKSPACE_ROOT/state/centurion-history.jsonl}"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/centurion-log.sh"
source "$SCRIPT_DIR/lib/centurion-test-gate.sh"
source "$SCRIPT_DIR/lib/centurion-semantic.sh"
source "$SCRIPT_DIR/lib/centurion-conflicts.sh"
source "$SCRIPT_DIR/lib/centurion-senate.sh"
source "$SCRIPT_DIR/lib/centurion-wake.sh"

TEST_GATE_LAST_OUTPUT=""
CENTURION_VERBOSE="${CENTURION_VERBOSE:-false}"
CENTURION_QUIET="${CENTURION_QUIET:-false}"

# ── Helpers ──────────────────────────────────────────────────────────────────

write_result() {
    local branch="$1" status="$2" repo_path="${3:-}" detail="${4:-}" quality_level="${5:-standard}" extra_json="${6:-}"
    [[ -n "$extra_json" ]] || extra_json='{}'
    mkdir -p "$CENTURION_RESULTS_DIR"
    local ts target tmp safe_branch
    ts="$(iso_now)"
    safe_branch="$(printf '%s' "$branch" | tr '/' '-')"
    target="$CENTURION_RESULTS_DIR/${safe_branch}-centurion.json"
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    jq -cn --arg branch "$branch" --arg status "$status" --arg repo "$repo_path" \
           --arg detail "$detail" --arg ts "$ts" --arg level "$quality_level" \
           --argjson extra "$extra_json" \
        '{branch:$branch, status:$status, repo:$repo, detail:$detail, quality_level:$level, extra:$extra, timestamp:$ts}' > "$tmp"
    mv "$tmp" "$target"
}

append_history() {
    local branch="$1" repo_path="$2" quality_level="$3" status="$4" checks="$5" detail="${6:-}"
    local duration_ms="$7"
    mkdir -p "$(dirname "$CENTURION_HISTORY_FILE")"
    jq -cn \
        --arg ts "$(iso_now)" \
        --arg branch "$branch" \
        --arg repo "$repo_path" \
        --arg level "$quality_level" \
        --arg status "$status" \
        --arg checks "$checks" \
        --arg detail "$detail" \
        --argjson duration_ms "${duration_ms:-0}" \
        '{timestamp:$ts, branch:$branch, repo:$repo, quality_level:$level, status:$status, checks:$checks, detail:$detail, duration_ms:$duration_ms}' \
        >> "$CENTURION_HISTORY_FILE"
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_merge() {
    local quality_level="$1" dry_run="$2" branch="$3" repo_path="$4"
    local merge_extra_json='{}'
    local started_epoch duration_ms
    started_epoch="$(epoch_now)"
    log_debug "Starting merge: branch=$branch repo=$repo_path level=$quality_level dry_run=$dry_run"

    case "$quality_level" in
        quick|standard|deep) ;;
        *)
            echo "Error: invalid quality level '$quality_level' (expected quick|standard|deep)" >&2
            exit 1
            ;;
    esac

    # Validate inputs
    git -C "$repo_path" rev-parse --git-dir &>/dev/null || {
        echo "Error: not a git repo: $repo_path" >&2
        exit 1
    }
    git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch" || {
        echo "Error: branch not found: $branch" >&2
        echo "  Available branches:" >&2
        git -C "$repo_path" branch --list 2>/dev/null | head -10 >&2
        exit 1
    }

    # Ensure main exists
    if ! git -C "$repo_path" show-ref --verify --quiet "refs/heads/main"; then
        if git -C "$repo_path" show-ref --verify --quiet "refs/heads/master"; then
            git -C "$repo_path" branch main master 2>/dev/null || true
        else
            echo "Error: no main or master branch in $repo_path" >&2
            exit 1
        fi
    fi

    # Refuse to merge if working tree is dirty
    if git -C "$repo_path" status --porcelain 2>/dev/null | grep -q .; then
        echo "Error: working tree is dirty in $repo_path" >&2
        echo "  Commit or stash changes before merging" >&2
        git -C "$repo_path" status --short >&2
        write_result "$branch" "dirty-worktree" "$repo_path" "uncommitted changes present" "$quality_level"
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "$branch" "$repo_path" "$quality_level" "dirty-worktree" "preflight" "uncommitted changes present" "$duration_ms"
        exit 1
    fi

    # Lock file to prevent concurrent merges to the same repo
    local lock_file="/tmp/centurion-$(printf '%s' "$repo_path" | sha256sum | cut -c1-12).lock"
    if [[ -f "$lock_file" ]]; then
        local lock_pid lock_age
        lock_pid="$(head -1 "$lock_file" 2>/dev/null)" || lock_pid=""
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "Error: another centurion merge is running for $repo_path (PID $lock_pid)" >&2
            echo "  Lock file: $lock_file" >&2
            exit 1
        fi
        # Stale lock — remove it
        log_info "Removing stale lock file (PID $lock_pid no longer running)"
        rm -f "$lock_file"
    fi
    echo "$$" > "$lock_file"
    # Clean up lock on exit
    local _prev_branch_for_cleanup=""
    _centurion_cleanup() {
        [[ -n "${lock_file:-}" ]] && rm -f "$lock_file"
        if [[ -n "${_prev_branch_for_cleanup:-}" ]]; then
            git -C "$repo_path" checkout "$_prev_branch_for_cleanup" 2>/dev/null || true
        fi
    }
    trap '_centurion_cleanup' EXIT

    local prev_branch
    prev_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)"
    _prev_branch_for_cleanup="$prev_branch"

    # Check if branch is already fully merged into main
    if git -C "$repo_path" merge-base --is-ancestor "$branch" main 2>/dev/null; then
        log_info "Branch $branch is already merged into main — nothing to do"
        write_result "$branch" "already-merged" "$repo_path" "" "$quality_level"
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "$branch" "$repo_path" "$quality_level" "already-merged" "preflight" "" "$duration_ms"
        exit 0
    fi

    git -C "$repo_path" checkout main >/dev/null 2>&1

    # Merge
    local merge_output
    if ! merge_output="$(git -C "$repo_path" merge --no-ff "$branch" -m "centurion: merge $branch to main" 2>&1)"; then
        local conflicts conflict_report
        conflicts="$(git -C "$repo_path" diff --name-only --diff-filter=U 2>/dev/null || echo "unknown")"
        conflict_report="$(collect_conflict_report "$repo_path")"
        if auto_resolve_trivial_conflicts "$repo_path"; then
            merge_extra_json="$(jq -cn --argjson report "$conflict_report" --argjson auto "$AUTO_RESOLUTION_LAST_JSON" \
                '{conflict_report:$report, auto_resolution:$auto}')"
            log_info "Auto-resolved trivial conflicts for $branch"
            notify_wake_gateway "Centurion: auto-resolved trivial conflict(s) for $branch"
        else
            local senate_case_file=""
            local senate_case_id=""
            local conflict_resolved_via_senate="false"
            merge_extra_json="$(jq -cn --argjson report "$conflict_report" --argjson auto "$AUTO_RESOLUTION_LAST_JSON" \
                '{conflict_report:$report, auto_resolution:$auto}')"
            if senate_case_file="$(escalate_to_senate "$repo_path" "$branch" "merge-conflict-unresolved" "$quality_level" "$conflict_report" "$AUTO_RESOLUTION_LAST_JSON")"; then
                senate_case_id="$(basename "$senate_case_file" .json)"
                merge_extra_json="$(jq -cn \
                    --argjson current "$merge_extra_json" \
                    --arg case_id "$senate_case_id" \
                    --arg case_file "$senate_case_file" \
                    '$current + {senate_escalation:{case_id:$case_id, case_file:$case_file, status:"pending"}}')"
                notify_wake_gateway "Centurion: escalated conflict for $branch to Senate ($senate_case_id)"

                if resolve_conflict_via_senate "$repo_path" "$senate_case_id"; then
                    conflict_resolved_via_senate="true"
                    merge_extra_json="$(jq -cn \
                        --argjson current "$merge_extra_json" \
                        --argjson resolution "$SENATE_RESOLUTION_LAST_JSON" \
                        '$current + {senate_resolution:$resolution}')"
                    log_info "Resolved conflict via Senate verdict for $branch"
                    notify_wake_gateway "Centurion: applied Senate verdict for $branch ($senate_case_id)"
                else
                    merge_extra_json="$(jq -cn \
                        --argjson current "$merge_extra_json" \
                        --argjson resolution "$SENATE_RESOLUTION_LAST_JSON" \
                        '$current + {senate_resolution:$resolution}')"
                fi
            fi

            if [[ "$conflict_resolved_via_senate" != "true" ]]; then
                write_result "$branch" "conflict" "$repo_path" "$conflicts" "$quality_level" "$merge_extra_json"
                notify_wake_gateway "Centurion: merge conflict for $branch ($conflicts)"
                git -C "$repo_path" merge --abort 2>/dev/null || true
                log_error "Merge conflict: $branch -> main"
                log_error "  Conflicting files: $conflicts"
                duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
                append_history "$branch" "$repo_path" "$quality_level" "conflict" "merge,conflict-analysis,senate" "$conflicts" "$duration_ms"
                exit 1
            fi
        fi
    fi

    # Mechanical quality gate
    if ! run_quality_gate "$repo_path" "$quality_level"; then
        write_result "$branch" "quality-failed" "$repo_path" "${TEST_GATE_LAST_OUTPUT:0:500}" "$quality_level" "$merge_extra_json"
        notify_wake_gateway "Centurion: quality gate failed for $branch (level=$quality_level)"
        git -C "$repo_path" reset --hard HEAD~1 >/dev/null
        log_error "Reverted: quality checks failed after merging $branch"
        log_error "  Quality output (last 200 chars): ${TEST_GATE_LAST_OUTPUT:0:200}"
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "$branch" "$repo_path" "$quality_level" "quality-failed" "${CENTURION_LAST_CHECKS:-quality}" "${TEST_GATE_LAST_OUTPUT:0:200}" "$duration_ms"
        exit 1
    fi

    # Deep mode semantic review
    if [[ "$quality_level" == "deep" ]]; then
        local semantic_rc=0 semantic_detail=""
        if run_semantic_review "$repo_path" "$branch" "main"; then
            semantic_rc=0
        else
            semantic_rc=$?
        fi
        semantic_detail="${SEMANTIC_REVIEW_LAST_JSON:-$SEMANTIC_REVIEW_LAST_SUMMARY}"

        case "$semantic_rc" in
            0)
                log_info "Semantic review passed"
                ;;
            1)
                write_result "$branch" "semantic-failed" "$repo_path" "${semantic_detail:0:500}" "$quality_level" "$merge_extra_json"
                notify_wake_gateway "Centurion: semantic review failed for $branch"
                git -C "$repo_path" reset --hard HEAD~1 >/dev/null
                log_error "Reverted: semantic review failed after merging $branch"
                log_error "  Semantic summary: ${SEMANTIC_REVIEW_LAST_SUMMARY:-failed}"
                duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
                append_history "$branch" "$repo_path" "$quality_level" "semantic-failed" "${CENTURION_LAST_CHECKS:-quality}" "${SEMANTIC_REVIEW_LAST_SUMMARY:-failed}" "$duration_ms"
                exit 1
                ;;
            *)
                write_result "$branch" "semantic-review-needed" "$repo_path" "${semantic_detail:0:500}" "$quality_level" "$merge_extra_json"
                notify_wake_gateway "Centurion: semantic review needs manual decision for $branch"
                git -C "$repo_path" reset --hard HEAD~1 >/dev/null
                log_error "Reverted: semantic review requested manual review for $branch"
                log_error "  Semantic summary: ${SEMANTIC_REVIEW_LAST_SUMMARY:-review-needed}"
                duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
                append_history "$branch" "$repo_path" "$quality_level" "semantic-review-needed" "${CENTURION_LAST_CHECKS:-quality}" "${SEMANTIC_REVIEW_LAST_SUMMARY:-review-needed}" "$duration_ms"
                exit 1
                ;;
        esac
    fi

    local commit_hash
    commit_hash="$(git -C "$repo_path" rev-parse --short HEAD)"
    if [[ "$dry_run" == "true" ]]; then
        git -C "$repo_path" reset --hard HEAD~1 >/dev/null
        write_result "$branch" "dry-run-pass" "$repo_path" "would-merge:$commit_hash" "$quality_level" "$merge_extra_json"
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "$branch" "$repo_path" "$quality_level" "dry-run-pass" "${CENTURION_LAST_CHECKS:-quality}" "$commit_hash" "$duration_ms"
        if [[ "$CENTURION_QUIET" == "true" ]]; then
            echo "PASS: dry-run would merge $branch to main at $commit_hash"
        else
            log_info "DRY RUN: would merge $branch to main at $commit_hash"
        fi
    else
        write_result "$branch" "merged" "$repo_path" "" "$quality_level" "$merge_extra_json"
        notify_wake_gateway "Centurion: merged $branch to main ($commit_hash, level=$quality_level)"
        _prev_branch_for_cleanup="" # Don't switch back — we want to stay on main after success
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "$branch" "$repo_path" "$quality_level" "merged" "${CENTURION_LAST_CHECKS:-quality}" "$commit_hash" "$duration_ms"
        if [[ "$CENTURION_QUIET" == "true" ]]; then
            echo "PASS: merged $branch to main at $commit_hash"
        else
            log_info "Merged $branch to main at $commit_hash"
        fi
    fi
}

cmd_status() {
    local repo_path="${1:-}"
    local -a repos=()

    if [[ -n "$repo_path" ]]; then
        repos=("$repo_path")
    else
        require_config
        mapfile -t repos < <(jq -r '.repos // {} | keys[]' "$CONFIG_FILE")
        [[ ${#repos[@]} -gt 0 ]] || { echo "No repos configured" >&2; exit 1; }
    fi

    for repo in "${repos[@]}"; do
        echo "Repo: $repo"
        git -C "$repo" rev-parse --git-dir &>/dev/null || { echo "  Not a git repo"; echo; continue; }

        local current main_head
        current="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
        echo "  Current branch: $current"

        if git -C "$repo" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
            main_head="$(git -C "$repo" log -1 --format='%h %s' main 2>/dev/null)"
            echo "  Main: $main_head"
        else
            echo "  Main: missing"
        fi

        local branches
        branches="$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ | grep -cv '^main$\|^master$\|^develop$' || echo 0)"
        echo "  Feature branches: $branches"
        echo
    done
}

cmd_history() {
    local limit="${1:-20}"
    [[ -n "$limit" ]] || limit=20
    is_integer "$limit" || limit=20

    if [[ ! -f "$CENTURION_HISTORY_FILE" ]]; then
        echo "No centurion history at $CENTURION_HISTORY_FILE"
        return 0
    fi

    tail -n "$limit" "$CENTURION_HISTORY_FILE" | jq -r \
        '"[\(.timestamp)] status=\(.status) branch=\(.branch) level=\(.quality_level) checks=\(.checks) duration_ms=\(.duration_ms)"'
}

cmd_check() {
    local repo_path="$1"
    local quality_level="${2:-quick}"
    local started_epoch duration_ms
    started_epoch="$(epoch_now)"

    case "$quality_level" in
        quick|standard|deep) ;;
        *)
            echo "Error: invalid quality level '$quality_level' (expected quick|standard|deep)" >&2
            return 1
            ;;
    esac

    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: not a git repo: $repo_path" >&2
        return 1
    fi

    if ! run_quality_gate "$repo_path" "$quality_level"; then
        log_error "Quality check failed for $repo_path (level=$quality_level)"
        log_error "  Output: ${TEST_GATE_LAST_OUTPUT:0:200}"
        duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
        append_history "check" "$repo_path" "$quality_level" "check-failed" "${CENTURION_LAST_CHECKS:-quality}" "${TEST_GATE_LAST_OUTPUT:0:200}" "$duration_ms"
        return 1
    fi

    if [[ "$quality_level" == "deep" ]]; then
        local current_branch
        current_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
        if [[ "$current_branch" != "main" ]] && git -C "$repo_path" show-ref --verify --quiet "refs/heads/main"; then
            if run_semantic_review "$repo_path" "$current_branch" "main"; then
                log_info "Semantic check passed for $current_branch"
            else
                log_error "Semantic check failed for $current_branch"
                duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
                append_history "check" "$repo_path" "$quality_level" "check-failed" "${CENTURION_LAST_CHECKS:-quality}" "${SEMANTIC_REVIEW_LAST_SUMMARY:-semantic-failed}" "$duration_ms"
                return 1
            fi
        else
            log_info "Deep semantic check skipped (requires non-main branch and local main)"
        fi
    fi

    duration_ms="$(( ( $(epoch_now) - started_epoch ) * 1000 ))"
    append_history "check" "$repo_path" "$quality_level" "check-passed" "${CENTURION_LAST_CHECKS:-quality}" "" "$duration_ms"
    if [[ "$CENTURION_QUIET" == "true" ]]; then
        echo "PASS: check passed for $repo_path (level=$quality_level)"
    else
        log_info "Quality check passed for $repo_path (level=$quality_level)"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() { sed -n '2,/^set /{ /^#/s/^# \?//p }' "$0"; }

case "${1:---help}" in
    merge)
        shift
        quality_level="standard"
        dry_run="false"
        while (( $# > 0 )); do
            case "$1" in
                --verbose)
                    CENTURION_VERBOSE="true"
                    shift
                    ;;
                --quiet)
                    CENTURION_QUIET="true"
                    shift
                    ;;
                --dry-run)
                    dry_run="true"
                    shift
                    ;;
                --level)
                    quality_level="${2:-}"
                    [[ -n "$quality_level" ]] || { echo "Error: --level requires a value" >&2; exit 1; }
                    shift 2
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                *)
                    break
                    ;;
            esac
        done
        (( $# >= 2 )) || { echo "Error: merge requires <branch> <repo-path>" >&2; exit 1; }
        centurion_log_init "$CENTURION_VERBOSE" "$CENTURION_QUIET"
        cmd_merge "$quality_level" "$dry_run" "$1" "$2"
        ;;
    status)
        shift
        while (( $# > 0 )); do
            case "$1" in
                --verbose)
                    CENTURION_VERBOSE="true"
                    shift
                    ;;
                --quiet)
                    CENTURION_QUIET="true"
                    shift
                    ;;
                *)
                    break
                    ;;
            esac
        done
        centurion_log_init "$CENTURION_VERBOSE" "$CENTURION_QUIET"
        cmd_status "${1:-}"
        ;;
    history)
        shift
        history_limit="20"
        while (( $# > 0 )); do
            case "$1" in
                --limit)
                    history_limit="${2:-20}"
                    shift 2
                    ;;
                --verbose)
                    CENTURION_VERBOSE="true"
                    shift
                    ;;
                --quiet)
                    CENTURION_QUIET="true"
                    shift
                    ;;
                *)
                    break
                    ;;
            esac
        done
        centurion_log_init "$CENTURION_VERBOSE" "$CENTURION_QUIET"
        cmd_history "$history_limit"
        ;;
    check)
        shift
        check_level="quick"
        while (( $# > 0 )); do
            case "$1" in
                --level)
                    check_level="${2:-quick}"
                    shift 2
                    ;;
                --verbose)
                    CENTURION_VERBOSE="true"
                    shift
                    ;;
                --quiet)
                    CENTURION_QUIET="true"
                    shift
                    ;;
                *)
                    break
                    ;;
            esac
        done
        check_repo="${1:-.}"
        centurion_log_init "$CENTURION_VERBOSE" "$CENTURION_QUIET"
        cmd_check "$check_repo" "$check_level"
        ;;
    --help|-h|help) usage ;;
    *)      echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac
