#!/usr/bin/env bash
# migrate-to-chrote.sh — Full migration from ahjo-1 VPS to chrote home server
# Run from VPS as perttu. Requires ssh access to chrote via Tailscale.
#
# Target setup on chrote:
#   - User: chrote (existing)
#   - OpenClaw profile: athena (--profile athena → ~/.openclaw-athena/)
#   - Gateway port: 18501
#   - Workspace: ~/athena/
#   - Existing bot (Mercury) untouched at ~/.openclaw/ port 18500
#
# Usage: ./scripts/migrate-to-chrote.sh [--dry-run]

set -euo pipefail

TARGET="chrote@100.102.1.26"
DRY=""
RSYNC_OPTS="-avz --progress"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY="--dry-run"
  RSYNC_OPTS="$RSYNC_OPTS --dry-run"
  echo "=== DRY RUN ==="
fi

echo "=== Step 1: Verify connectivity ==="
ssh "$TARGET" "echo 'Connected to \$(hostname)'" || { echo "FATAL: can't reach chrote"; exit 1; }

echo ""
echo "=== Step 2: Sync Agora repos ==="
for dir in athena argus truthsayer oathkeeper relay learning-loop ludus-magnus agent-agora athena-web; do
  if [[ -d ~/$dir ]]; then
    echo "--- $dir ---"
    rsync $RSYNC_OPTS ~/$dir/ "$TARGET":~/$dir/
  fi
done

echo ""
echo "=== Step 3: Sync other projects ==="
for dir in gws-agent-factory moonshot-research Agora ai-master-trainer Agent_acadmey meta_skill beads-repo; do
  if [[ -d ~/$dir ]]; then
    echo "--- $dir ---"
    rsync $RSYNC_OPTS ~/$dir/ "$TARGET":~/$dir/
  fi
done

echo ""
echo "=== Step 4: Sync Go binaries ==="
# These go alongside existing blogwatcher/gopls — no conflicts
rsync $RSYNC_OPTS ~/go/bin/bd "$TARGET":~/go/bin/
rsync $RSYNC_OPTS ~/go/bin/truthsayer "$TARGET":~/go/bin/
rsync $RSYNC_OPTS ~/go/bin/oathkeeper "$TARGET":~/go/bin/
rsync $RSYNC_OPTS ~/go/bin/relay "$TARGET":~/go/bin/
rsync $RSYNC_OPTS ~/go/bin/ntm "$TARGET":~/go/bin/

echo ""
echo "=== Step 5: Sync OpenClaw state to athena profile ==="
# IMPORTANT: goes to ~/.openclaw-athena/, NOT ~/.openclaw/ (that's Mercury)
rsync $RSYNC_OPTS ~/.openclaw/ "$TARGET":~/.openclaw-athena/ \
  --exclude='openclaw.json'  # Config needs manual setup for new host

echo ""
echo "=== Step 6: Sync shell config additions ==="
# Don't overwrite — append what's needed
echo "NOTE: Review PATH additions needed on chrote:"
echo '  export PATH="$HOME/go/bin:/usr/local/go/bin:$HOME/.npm-global/bin:$PATH"'

echo ""
echo "=== Step 7: Export cron ==="
crontab -l > /tmp/ahjo-crontab.txt 2>/dev/null || true
scp /tmp/ahjo-crontab.txt "$TARGET":/tmp/ahjo-crontab.txt
echo "NOTE: Review and merge into chrote's crontab (don't replace — they have their own)"

echo ""
echo "=== Step 8: Sync Agora assets ==="
if [[ -d ~/Agora ]]; then
  rsync $RSYNC_OPTS ~/Agora/ "$TARGET":~/Agora/
fi

echo ""
echo "=== SYNC COMPLETE ==="
echo ""
cat <<'EOF'

MANUAL STEPS ON CHROTE:

1. Install Go toolchain (not currently in PATH):
   wget https://go.dev/dl/go1.26.0.linux-amd64.tar.gz
   sudo tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz

2. Add to PATH (in ~/.bashrc or ~/.profile):
   export PATH="$HOME/go/bin:/usr/local/go/bin:$HOME/.npm-global/bin:$PATH"

3. Set up Athena's OpenClaw profile:
   openclaw --profile athena setup
   openclaw --profile athena onboard
   # Configure: Telegram webhook, API keys, model settings
   # Edit ~/.openclaw-athena/openclaw.json

4. Start Athena's gateway:
   openclaw --profile athena gateway --port 18501
   # Or create a systemd service for it

5. Tailscale Funnel for Telegram webhook:
   tailscale funnel 18501
   # Use the funnel URL as Telegram webhook endpoint

6. Merge cron (don't replace):
   cat /tmp/ahjo-crontab.txt
   # Add relevant entries to existing crontab: crontab -e

7. Verify everything:
   bd --version                          # expect 0.46.0
   truthsayer scan ~/athena/scripts/     # should work
   oathkeeper --help
   relay --help
   openclaw --profile athena status
   curl http://localhost:18501            # athena gateway

8. Update git identity on chrote if needed:
   git config --global user.name "Perttulands"
   git config --global user.email "194203783+Perttulands@users.noreply.github.com"

PORTS:
  Mercury (existing): 18500 (default)
  Athena (new):       18501
  Athena Web:         9000 (if deployed)

EOF
