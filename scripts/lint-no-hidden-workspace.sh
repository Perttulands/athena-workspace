#!/usr/bin/env bash
# lint-no-hidden-workspace.sh
#
# Guardrail: prevent hardcoded hidden workspace/log paths from re-entering
# active code/docs. Historical archive docs are excluded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Tracked files only; exclude historical archive and this script itself.
if git grep -nE '\.openclaw/workspace|\.openclaw/logs' -- \
    . \
    ':(exclude)docs/archive/**' \
    ':(exclude)scripts/lint-no-hidden-workspace.sh' \
    > /tmp/athena-hidden-workspace-lint.out; then
    echo "Error: legacy hidden workspace/log paths detected in active files:" >&2
    cat /tmp/athena-hidden-workspace-lint.out >&2
    echo "" >&2
    echo "Use ATHENA_WORKSPACE/OPENCLAW_HOME or \$HOME/athena in docs/examples." >&2
    rm -f /tmp/athena-hidden-workspace-lint.out
    exit 1
fi

rm -f /tmp/athena-hidden-workspace-lint.out
echo "PASS: no legacy hidden workspace/log paths in active files"
