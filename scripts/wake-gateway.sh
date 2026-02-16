#!/usr/bin/env bash
# Wake the OpenClaw gateway (triggers heartbeat).
# Usage: wake-gateway.sh [text]
# Uses OpenClaw's own callGateway to avoid handshake complexity.
set -euo pipefail

TEXT="${1:-agent completed}"

node -e "
const { n: callGateway } = require(process.env.HOME + '/.npm-global/lib/node_modules/openclaw/dist/call-DLNOeLcz.js');
callGateway({
  method: 'wake',
  params: { mode: 'now', text: process.argv[1] },
  timeoutMs: 10000,
  clientName: 'cli',
  mode: 'cli'
}).then(r => { console.log(JSON.stringify(r)); process.exit(0); })
  .catch(e => { console.error('wake failed:', e.message); process.exit(1); });
" "$TEXT"
