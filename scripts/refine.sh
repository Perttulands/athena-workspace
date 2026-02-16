#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/refine.sh <repo-path> [--branches branch1,branch2,...] [--agent codex|claude] [--model high|opus] [--dry-run]

Options:
  --branches  Comma-separated refs to merge before refinement.
  --agent     Agent type for dispatch (default: codex).
  --model     codex: high, claude: opus (defaults follow agent).
  --dry-run   Show planned actions without executing them.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "required command not found: $1"
    fi
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

close_bead() {
    local bead_id="$1"
    local reason="$2"
    if [[ -n "$bead_id" ]]; then
        if ! br close "$bead_id" --reason "$reason" >/dev/null 2>&1; then
            echo "Warning: failed to close bead $bead_id ($reason)" >&2
        fi
    fi
}

launch_bead_close_watcher() {
    local bead_id="$1"
    local results_dir="$2"
    local result_file="$results_dir/$bead_id.json"

    (
        set +e
        local timeout_seconds=7200
        local interval_seconds=10
        local elapsed=0
        local status=""
        local reason="refinement run ended"

        while (( elapsed < timeout_seconds )); do
            if [[ -f "$result_file" ]]; then
                if ! status="$(jq -r '.status // empty' "$result_file")"; then
                    echo "Warning: invalid result file while watching bead $bead_id: $result_file" >&2
                    status=""
                fi
                case "$status" in
                    done)
                        reason="refinement completed"
                        break
                        ;;
                    failed)
                        reason="refinement failed"
                        break
                        ;;
                    timeout)
                        reason="refinement timed out"
                        break
                        ;;
                esac
            fi
            sleep "$interval_seconds"
            elapsed=$((elapsed + interval_seconds))
        done

        if [[ -z "$status" ]]; then
            reason="refinement watcher timeout"
        fi
        if ! br close "$bead_id" --reason "$reason" >/dev/null 2>&1; then
            echo "Warning: watcher failed to close bead $bead_id ($reason)" >&2
        fi
    ) >/dev/null 2>&1 &
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH_SCRIPT="$SCRIPT_DIR/dispatch.sh"
TEMPLATE_FILE="$WORKSPACE_ROOT/templates/refine.md"
RESULTS_DIR="$WORKSPACE_ROOT/state/results"

REPO_INPUT=""
BRANCHES_CSV=""
AGENT="codex"
MODEL=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branches)
            [[ $# -ge 2 ]] || die "--branches requires a value"
            BRANCHES_CSV="$2"
            shift 2
            ;;
        --agent)
            [[ $# -ge 2 ]] || die "--agent requires a value"
            AGENT="$2"
            shift 2
            ;;
        --model)
            [[ $# -ge 2 ]] || die "--model requires a value"
            MODEL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            if [[ -z "$REPO_INPUT" ]]; then
                REPO_INPUT="$1"
            else
                die "unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

[[ -n "$REPO_INPUT" ]] || {
    usage
    exit 1
}

case "$AGENT" in
    codex|claude) ;;
    *) die "--agent must be codex or claude" ;;
esac

if [[ -z "$MODEL" ]]; then
    if [[ "$AGENT" == "codex" ]]; then
        MODEL="high"
    else
        MODEL="opus"
    fi
fi

case "$MODEL" in
    high|opus) ;;
    *) die "--model must be high or opus" ;;
esac

if [[ "$AGENT" == "codex" && "$MODEL" != "high" ]]; then
    die "codex only supports --model high in refine.sh"
fi
if [[ "$AGENT" == "claude" && "$MODEL" != "opus" ]]; then
    die "claude only supports --model opus in refine.sh"
fi

if [[ "$REPO_INPUT" != /* ]]; then
    REPO_INPUT="$(pwd)/$REPO_INPUT"
fi
[[ -d "$REPO_INPUT" ]] || die "repo path does not exist: $REPO_INPUT"
REPO_PATH="$(cd "$REPO_INPUT" && pwd)"

[[ -d "$REPO_PATH/.git" ]] || die "repo is not a git repository: $REPO_PATH"
[[ -x "$DISPATCH_SCRIPT" ]] || die "dispatch script missing or not executable: $DISPATCH_SCRIPT"
[[ -f "$TEMPLATE_FILE" ]] || die "template file not found: $TEMPLATE_FILE"

require_cmd git
require_cmd jq
require_cmd br

REPO_NAME="$(basename "$REPO_PATH")"
BEAD_TITLE="Refinement pass for $REPO_NAME"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
REFINE_BRANCH="refine/$TIMESTAMP"

declare -a BRANCHES=()
if [[ -n "$BRANCHES_CSV" ]]; then
    IFS=',' read -r -a raw_branches <<< "$BRANCHES_CSV"
    for raw in "${raw_branches[@]}"; do
        branch="$(trim "$raw")"
        [[ -n "$branch" ]] || continue
        if ! git -C "$REPO_PATH" rev-parse --verify "${branch}^{commit}" >/dev/null 2>&1; then
            die "branch/ref not found: $branch"
        fi
        BRANCHES+=("$branch")
    done
    [[ ${#BRANCHES[@]} -gt 0 ]] || die "--branches did not contain any valid refs"
fi

if [[ ${#BRANCHES[@]} -gt 0 && "$DRY_RUN" != "true" ]]; then
    if ! git -C "$REPO_PATH" diff --quiet --ignore-submodules --; then
        die "working tree has unstaged changes; commit or stash before merging branches"
    fi
    if ! git -C "$REPO_PATH" diff --cached --quiet --ignore-submodules --; then
        die "working tree has staged changes; commit or stash before merging branches"
    fi
fi

BRANCHES_BLOCK=""
if [[ ${#BRANCHES[@]} -gt 0 ]]; then
    BRANCHES_BLOCK+="Refinement branch: $REFINE_BRANCH"$'\n'
    for branch in "${BRANCHES[@]}"; do
        sha="$(git -C "$REPO_PATH" rev-parse --short "${branch}^{commit}")"
        BRANCHES_BLOCK+="- $branch ($sha)"$'\n'
    done
else
    head_sha="$(git -C "$REPO_PATH" rev-parse --short HEAD)"
    BRANCHES_BLOCK+="- current HEAD ($head_sha)"$'\n'
fi
BRANCHES_BLOCK="${BRANCHES_BLOCK%$'\n'}"

PROJECT_CONTEXT_SOURCE=""
if [[ -f "$REPO_PATH/README.md" ]]; then
    PROJECT_CONTEXT_SOURCE="$REPO_PATH/README.md"
elif [[ -f "$REPO_PATH/CLAUDE.md" ]]; then
    PROJECT_CONTEXT_SOURCE="$REPO_PATH/CLAUDE.md"
fi

if [[ -n "$PROJECT_CONTEXT_SOURCE" ]]; then
    PROJECT_CONTEXT="Source: $(basename "$PROJECT_CONTEXT_SOURCE")"$'\n\n'"$(cat "$PROJECT_CONTEXT_SOURCE")"
else
    PROJECT_CONTEXT="No README.md or CLAUDE.md was found in repository root."
fi

TEMPLATE_CONTENT="$(cat "$TEMPLATE_FILE")"
PROMPT="${TEMPLATE_CONTENT//\{BRANCHES\}/$BRANCHES_BLOCK}"
PROMPT="${PROMPT//\{PROJECT_CONTEXT\}/$PROJECT_CONTEXT}"

if [[ "$PROMPT" == *"{BRANCHES}"* || "$PROMPT" == *"{PROJECT_CONTEXT}"* ]]; then
    die "template placeholder substitution failed"
fi

declare -a DISPATCH_ENV=()
if [[ "$AGENT" == "codex" ]]; then
    # Codex CLI exposes reasoning effort through config override keys.
    DISPATCH_ENV+=("DISPATCH_CODEX_REASONING_EFFORT=high")
else
    DISPATCH_ENV+=("DISPATCH_CLAUDE_MODEL=opus")
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: refine.sh"
    echo "Repository: $REPO_PATH"
    echo "Bead title: $BEAD_TITLE"
    echo "Agent: $AGENT"
    echo "Model: $MODEL"
    if [[ ${#BRANCHES[@]} -gt 0 ]]; then
        echo "Would create branch: $REFINE_BRANCH"
        printf 'Would merge refs: %s\n' "$(IFS=,; echo "${BRANCHES[*]}")"
    else
        echo "Would use current HEAD (no branch merge step)"
    fi
    if [[ -n "$PROJECT_CONTEXT_SOURCE" ]]; then
        echo "Project context source: $PROJECT_CONTEXT_SOURCE"
    else
        echo "Project context source: none (fallback text)"
    fi
    echo "Would run:"
    printf '  env %s %q %q %q %q %q\n' \
        "$(printf '%s ' "${DISPATCH_ENV[@]}" | sed 's/[[:space:]]*$//')" \
        "$DISPATCH_SCRIPT" \
        "<bead-id>" \
        "$REPO_PATH" \
        "$AGENT" \
        "<prompt>"
    echo
    echo "Prompt preview:"
    echo "----------------------------------------"
    printf '%s\n' "$PROMPT"
    echo "----------------------------------------"
    exit 0
fi

if ! create_json="$(br create --title "$BEAD_TITLE" --priority 1 --json)"; then
    die "failed to create bead for refinement pass"
fi
if ! BEAD_ID="$(printf '%s' "$create_json" | jq -r '.id // empty')"; then
    die "failed to parse bead creation output"
fi
[[ -n "$BEAD_ID" ]] || die "failed to create bead for refinement pass"

echo "Created bead: $BEAD_ID"

if [[ ${#BRANCHES[@]} -gt 0 ]]; then
    echo "Creating branch: $REFINE_BRANCH"
    if ! git -C "$REPO_PATH" checkout -b "$REFINE_BRANCH"; then
        close_bead "$BEAD_ID" "refinement setup failed: branch create"
        die "failed to create branch: $REFINE_BRANCH"
    fi

    for branch in "${BRANCHES[@]}"; do
        echo "Merging: $branch"
        if ! git -C "$REPO_PATH" merge --no-ff --no-edit "$branch"; then
            echo "Merge failed for ref: $branch" >&2
            if git -C "$REPO_PATH" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
                if ! git -C "$REPO_PATH" merge --abort >/dev/null 2>&1; then
                    echo "Warning: failed to abort merge after conflict on $branch" >&2
                fi
            fi
            close_bead "$BEAD_ID" "refinement setup failed: merge conflict on $branch"
            exit 1
        fi
    done
fi

set +e
dispatch_output="$(env "${DISPATCH_ENV[@]}" "$DISPATCH_SCRIPT" "$BEAD_ID" "$REPO_PATH" "$AGENT" "$PROMPT" "refine" 2>&1)"
dispatch_exit=$?
set -e

printf '%s\n' "$dispatch_output"

if [[ $dispatch_exit -ne 0 ]]; then
    close_bead "$BEAD_ID" "refinement dispatch failed"
    die "dispatch failed for bead $BEAD_ID"
fi

launch_bead_close_watcher "$BEAD_ID" "$RESULTS_DIR"

echo "Refinement dispatched under bead $BEAD_ID. Bead will close automatically on terminal status."
