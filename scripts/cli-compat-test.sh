#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_FILE="$WORKSPACE_ROOT/state/cli-compat-report.md"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

has_fragment() {
    local text="$1"
    local fragment="$2"
    if grep -Fq -- "$fragment" <<< "$text"; then
        echo "yes"
    else
        echo "no"
    fi
}

bool_word() {
    local value="$1"
    if [[ "$value" == "yes" ]]; then
        echo "pass"
    else
        echo "fail"
    fi
}

require_cmd claude
require_cmd codex

if ! CLAUDE_HELP="$(claude --help 2>&1)"; then
    echo "Error: failed to run 'claude --help'" >&2
    echo "$CLAUDE_HELP" >&2
    exit 1
fi
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

CLAUDE_PRINT="$(has_fragment "$CLAUDE_HELP" "-p, --print")"
CLAUDE_APPEND_SYSTEM_PROMPT="$(has_fragment "$CLAUDE_HELP" "--append-system-prompt")"
CLAUDE_AGENT="$(has_fragment "$CLAUDE_HELP" "--agent")"
CLAUDE_AGENTS="$(has_fragment "$CLAUDE_HELP" "--agents")"
CLAUDE_DANGEROUS="$(has_fragment "$CLAUDE_HELP" "--dangerously-skip-permissions")"

CODEX_EXEC="$(has_fragment "$CODEX_HELP" "exec")"
CODEX_PROFILE="$(has_fragment "$CODEX_HELP" "--profile")"
CODEX_FULL_AUTO="$(has_fragment "$CODEX_HELP" "--full-auto")"
CODEX_STDIN_PROMPT="$(has_fragment "$CODEX_EXEC_HELP" "read from stdin")"
CODEX_DANGEROUS="$(has_fragment "$CODEX_HELP" "--dangerously-bypass-approvals-and-sandbox")"

FAILURES=0

require_pass() {
    local label="$1"
    local value="$2"
    if [[ "$value" != "yes" ]]; then
        echo "FAIL: $label" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

require_pass "claude -p/--print" "$CLAUDE_PRINT"
require_pass "claude --append-system-prompt" "$CLAUDE_APPEND_SYSTEM_PROMPT"
require_pass "claude --agent" "$CLAUDE_AGENT"
require_pass "claude --agents" "$CLAUDE_AGENTS"
require_pass "codex exec" "$CODEX_EXEC"
require_pass "codex --profile" "$CODEX_PROFILE"
require_pass "codex --full-auto" "$CODEX_FULL_AUTO"
require_pass "codex exec stdin prompt support" "$CODEX_STDIN_PROMPT"

mkdir -p "$(dirname "$REPORT_FILE")"
cat > "$REPORT_FILE" <<EOF
# CLI Compatibility Report

Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Equivalent capabilities
- Non-interactive execution:
  - Claude: $CLAUDE_PRINT ($(bool_word "$CLAUDE_PRINT"))
  - Codex: $CODEX_EXEC ($(bool_word "$CODEX_EXEC"))
- Stdin prompt input:
  - Claude print mode available: $CLAUDE_PRINT ($(bool_word "$CLAUDE_PRINT"))
  - Codex exec stdin support: $CODEX_STDIN_PROMPT ($(bool_word "$CODEX_STDIN_PROMPT"))
- Dangerous bypass flag:
  - Claude: $CLAUDE_DANGEROUS ($(bool_word "$CLAUDE_DANGEROUS"))
  - Codex: $CODEX_DANGEROUS ($(bool_word "$CODEX_DANGEROUS"))

## Different capabilities
- Claude-only options:
  - --append-system-prompt: $CLAUDE_APPEND_SYSTEM_PROMPT ($(bool_word "$CLAUDE_APPEND_SYSTEM_PROMPT"))
  - --agent: $CLAUDE_AGENT ($(bool_word "$CLAUDE_AGENT"))
  - --agents: $CLAUDE_AGENTS ($(bool_word "$CLAUDE_AGENTS"))
- Codex-only option:
  - --profile: $CODEX_PROFILE ($(bool_word "$CODEX_PROFILE"))
  - --full-auto: $CODEX_FULL_AUTO ($(bool_word "$CODEX_FULL_AUTO"))
EOF

cat "$REPORT_FILE"

if (( FAILURES > 0 )); then
    echo "cli-compat-test: $FAILURES required checks failed" >&2
    exit 1
fi

echo "cli-compat-test: all required checks passed"
