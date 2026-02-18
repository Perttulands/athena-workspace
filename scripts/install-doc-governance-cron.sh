#!/usr/bin/env bash
# install-doc-governance-cron.sh - Install weekly doc governance cron job

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/paths.sh
source "$WORKSPACE_ROOT/scripts/lib/paths.sh"

LOG_DIR="$ATHENA_WORKSPACE/state/logs"
mkdir -p "$LOG_DIR"

CRON_TAG="# athena-doc-governance-weekly"
CRON_CMD="30 5 * * 1 $ATHENA_WORKSPACE/scripts/doc-governance-weekly.sh >> $LOG_DIR/doc-governance-weekly.log 2>&1 $CRON_TAG"

existing="$(crontab -l 2>/dev/null || true)"

if printf '%s\n' "$existing" | grep -Fq "$CRON_TAG"; then
    echo "Cron entry already installed."
    exit 0
fi

{
    printf '%s\n' "$existing"
    printf '%s\n' "$CRON_CMD"
} | sed '/^[[:space:]]*$/d' | crontab -

echo "Installed weekly doc governance cron entry."
