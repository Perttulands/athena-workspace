#!/usr/bin/env bash
# centurion.sh — Merge a branch to main with test gate
#
# Usage:
#   centurion.sh merge <branch> <repo-path>    Merge branch into main (test-gated)
#   centurion.sh status [repo-path]             Show branch/merge status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WAKE_GATEWAY_BIN="${CENTURION_WAKE_BIN:-$SCRIPT_DIR/wake-gateway.sh}"
CENTURION_RESULTS_DIR="${CENTURION_RESULTS_DIR:-$WORKSPACE_ROOT/state/results}"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/centurion-test-gate.sh"
source "$SCRIPT_DIR/lib/centurion-wake.sh"

TEST_GATE_LAST_OUTPUT=""

# ── Helpers ──────────────────────────────────────────────────────────────────

write_result() {
    local branch="$1" status="$2" repo_path="${3:-}" detail="${4:-}"
    mkdir -p "$CENTURION_RESULTS_DIR"
    local ts target tmp safe_branch
    ts="$(iso_now)"
    safe_branch="$(printf '%s' "$branch" | tr '/' '-')"
    target="$CENTURION_RESULTS_DIR/${safe_branch}-centurion.json"
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    jq -cn --arg branch "$branch" --arg status "$status" --arg repo "$repo_path" \
           --arg detail "$detail" --arg ts "$ts" \
        '{branch:$branch, status:$status, repo:$repo, detail:$detail, timestamp:$ts}' > "$tmp"
    mv "$tmp" "$target"
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_merge() {
    local branch="$1" repo_path="$2"

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
        write_result "$branch" "dirty-worktree" "$repo_path" "uncommitted changes present"
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
        echo "Removing stale lock file (PID $lock_pid no longer running)"
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
        echo "Branch $branch is already merged into main — nothing to do"
        write_result "$branch" "already-merged" "$repo_path"
        exit 0
    fi

    git -C "$repo_path" checkout main >/dev/null 2>&1

    # Merge
    local merge_output
    if ! merge_output="$(git -C "$repo_path" merge --no-ff "$branch" -m "centurion: merge $branch to main" 2>&1)"; then
        local conflicts
        conflicts="$(git -C "$repo_path" diff --name-only --diff-filter=U 2>/dev/null || echo "unknown")"
        write_result "$branch" "conflict" "$repo_path" "$conflicts"
        notify_wake_gateway "Centurion: merge conflict for $branch ($conflicts)"
        git -C "$repo_path" merge --abort 2>/dev/null || true
        echo "Merge conflict: $branch → main" >&2
        echo "  Conflicting files: $conflicts" >&2
        exit 1
    fi

    # Test gate
    if ! run_test_gate "$repo_path"; then
        write_result "$branch" "test-failed" "$repo_path" "${TEST_GATE_LAST_OUTPUT:0:500}"
        notify_wake_gateway "Centurion: test gate failed for $branch"
        git -C "$repo_path" reset --hard HEAD~1 >/dev/null
        echo "Reverted: tests failed after merging $branch" >&2
        echo "  Test output (last 200 chars): ${TEST_GATE_LAST_OUTPUT:0:200}" >&2
        exit 1
    fi

    local commit_hash
    commit_hash="$(git -C "$repo_path" rev-parse --short HEAD)"
    write_result "$branch" "merged" "$repo_path"
    notify_wake_gateway "Centurion: merged $branch to main ($commit_hash)"
    _prev_branch_for_cleanup="" # Don't switch back — we want to stay on main after success
    echo "Merged $branch to main at $commit_hash"
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

# ── Main ─────────────────────────────────────────────────────────────────────

usage() { sed -n '2,/^set /{ /^#/s/^# \?//p }' "$0"; }

case "${1:---help}" in
    merge)  (( $# >= 3 )) || { echo "Error: merge requires <branch> <repo-path>" >&2; exit 1; }; cmd_merge "$2" "$3" ;;
    status) cmd_status "${2:-}" ;;
    --help|-h|help) usage ;;
    *)      echo "Error: unknown command '$1'" >&2; usage; exit 1 ;;
esac
