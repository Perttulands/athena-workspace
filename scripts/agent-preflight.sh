#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [claude|codex|both] [repo-path]" >&2
}

AGENT_TYPE="${1:-both}"
REPO_PATH="${2:-$(pwd)}"

if [[ "$AGENT_TYPE" != "claude" && "$AGENT_TYPE" != "codex" && "$AGENT_TYPE" != "both" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$REPO_PATH" ]]; then
    echo "Error: repo path does not exist: $REPO_PATH" >&2
    exit 1
fi

if [[ ! -w "$REPO_PATH" ]]; then
    echo "Error: repo path is not writable: $REPO_PATH" >&2
    exit 1
fi

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

require_contains() {
    local text="$1"
    local needle="$2"
    local label="$3"
    if ! grep -Fq -- "$needle" <<< "$text"; then
        echo "Error: missing expected feature '$label' ($needle)" >&2
        exit 1
    fi
}

require_cmd jq
require_cmd tmux
require_cmd openclaw

if [[ "$AGENT_TYPE" == "claude" || "$AGENT_TYPE" == "both" ]]; then
    require_cmd claude
    if ! CLAUDE_HELP="$(claude --help 2>&1)"; then
        echo "Error: failed to run 'claude --help'" >&2
        echo "$CLAUDE_HELP" >&2
        exit 1
    fi
    require_contains "$CLAUDE_HELP" "-p, --print" "claude print mode"
    require_contains "$CLAUDE_HELP" "--append-system-prompt" "claude append system prompt"
    require_contains "$CLAUDE_HELP" "--agent" "claude named agent selector"
    require_contains "$CLAUDE_HELP" "--agents" "claude custom agent definitions"
fi

if [[ "$AGENT_TYPE" == "codex" || "$AGENT_TYPE" == "both" ]]; then
    require_cmd codex
    if ! CODEX_HELP="$(codex --help 2>&1)"; then
        echo "Error: failed to run 'codex --help'" >&2
        echo "$CODEX_HELP" >&2
        exit 1
    fi
    if ! CODEX_EXEC_HELP="$(codex exec --help 2>&1)"; then
        echo "Error: failed to run 'codex exec --help'" >&2
        echo "$CODEX_EXEC_HELP" >&2
        exit 1
    fi
    require_contains "$CODEX_HELP" "exec" "codex non-interactive command"
    require_contains "$CODEX_HELP" "--profile" "codex profile selector"
    require_contains "$CODEX_HELP" "--full-auto" "codex full-auto mode"
    require_contains "$CODEX_EXEC_HELP" "read from stdin" "codex exec stdin prompt support"

    # Check if repo is a git repository (codex requires this unless --skip-git-repo-check is used)
    if [[ ! -d "$REPO_PATH/.git" ]]; then
        echo "Warning: '$REPO_PATH' is not a git repository. Codex will use --skip-git-repo-check." >&2
    fi
fi

echo "agent-preflight OK: agent_type=$AGENT_TYPE repo=$REPO_PATH"
