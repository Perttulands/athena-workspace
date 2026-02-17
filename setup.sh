#!/usr/bin/env bash
# setup.sh — Bootstrap the Athena workspace on a fresh VPS
# Run this after cloning the repo into ~/.openclaw/workspace/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

# ── Step 1: Check prerequisites ─────────────────────────────────────────────
info "Checking prerequisites..."

MISSING=()
for cmd in git jq rg tmux; do
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd found"
    else
        fail "$cmd not found"
        MISSING+=("$cmd")
    fi
done

# Optional but recommended
for cmd in go node claude codex bd gh; do
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd found"
    else
        warn "$cmd not found (optional, needed for full functionality)"
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    fail "Missing required tools: ${MISSING[*]}"
    echo "Install them before continuing."
    exit 1
fi

# ── Step 2: Gather configuration ────────────────────────────────────────────
echo ""
info "Gathering configuration..."
echo "Press Enter to accept defaults shown in [brackets]."
echo ""

# Allow environment variables to pre-fill
DEFAULT_USER="${ATHENA_USER:-$(whoami)}"
DEFAULT_HOME="${ATHENA_HOME:-$HOME}"
DEFAULT_HOSTNAME="${ATHENA_HOSTNAME:-$(hostname)}"
DEFAULT_TAILSCALE_IP="${ATHENA_TAILSCALE_IP:-}"
DEFAULT_GITHUB_USER="${ATHENA_GITHUB_USER:-}"

read -rp "Username [$DEFAULT_USER]: " USERNAME
USERNAME="${USERNAME:-$DEFAULT_USER}"

read -rp "Home directory [$DEFAULT_HOME]: " HOME_DIR
HOME_DIR="${HOME_DIR:-$DEFAULT_HOME}"

read -rp "Server hostname [$DEFAULT_HOSTNAME]: " HOSTNAME_VAL
HOSTNAME_VAL="${HOSTNAME_VAL:-$DEFAULT_HOSTNAME}"

if [[ -z "$DEFAULT_TAILSCALE_IP" ]] && command -v tailscale &>/dev/null; then
    DEFAULT_TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo "")"
fi
read -rp "Tailscale IP [$DEFAULT_TAILSCALE_IP]: " TAILSCALE_IP
TAILSCALE_IP="${TAILSCALE_IP:-$DEFAULT_TAILSCALE_IP}"

read -rp "GitHub username [$DEFAULT_GITHUB_USER]: " GITHUB_USER
GITHUB_USER="${GITHUB_USER:-$DEFAULT_GITHUB_USER}"

# ── Step 3: Create directories ──────────────────────────────────────────────
echo ""
info "Creating directories..."

DIRS=(
    memory
    state/runs
    state/results
    state/watch
    state/truthsayer
    state/archive/runs
    state/archive/results
    state/calibration
    state/plans
    state/verifications
    state/reviews
    state/designs
    .beads
    inbox/incoming
    inbox/processing
    inbox/done
    inbox/failed
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$SCRIPT_DIR/$dir"
    ok "Created $dir/"
done

# ── Step 4: Generate config files from .example templates ────────────────────
echo ""
info "Generating config files from .example templates..."

replace_placeholders() {
    local src="$1" dst="$2"
    if [[ -f "$dst" ]]; then
        warn "$dst already exists, skipping (remove it to regenerate)"
        return
    fi
    sed \
        -e "s|{{USERNAME}}|$USERNAME|g" \
        -e "s|{{HOME}}|$HOME_DIR|g" \
        -e "s|{{HOSTNAME}}|$HOSTNAME_VAL|g" \
        -e "s|{{TAILSCALE_IP}}|$TAILSCALE_IP|g" \
        -e "s|{{GITHUB_USER}}|$GITHUB_USER|g" \
        "$src" > "$dst"
    ok "Generated $dst"
}

replace_placeholders "$SCRIPT_DIR/TOOLS.md.example" "$SCRIPT_DIR/TOOLS.md"
replace_placeholders "$SCRIPT_DIR/config/agents.json.example" "$SCRIPT_DIR/config/agents.json"
replace_placeholders "$SCRIPT_DIR/MEMORY.md.example" "$SCRIPT_DIR/MEMORY.md"

# ── Step 5: Make scripts executable ─────────────────────────────────────────
echo ""
info "Making scripts executable..."

find "$SCRIPT_DIR/scripts" -name '*.sh' -exec chmod +x {} \;
find "$SCRIPT_DIR/tests" -name '*.sh' -exec chmod +x {} \;
find "$SCRIPT_DIR/skills" -name '*.sh' -exec chmod +x {} \;
chmod +x "$SCRIPT_DIR/setup.sh"
ok "All scripts are executable"

# ── Step 6: Validate generated JSON ─────────────────────────────────────────
echo ""
info "Validating generated files..."

if [[ -f "$SCRIPT_DIR/config/agents.json" ]]; then
    if jq empty "$SCRIPT_DIR/config/agents.json" 2>/dev/null; then
        ok "config/agents.json is valid JSON"
    else
        fail "config/agents.json is invalid JSON — please check placeholders"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "==========================================="
echo "  Athena Workspace Setup Complete"
echo "==========================================="
echo ""
echo "  User:       $USERNAME"
echo "  Home:       $HOME_DIR"
echo "  Hostname:   $HOSTNAME_VAL"
echo "  Tailscale:  ${TAILSCALE_IP:-<not set>}"
echo "  GitHub:     ${GITHUB_USER:-<not set>}"
echo ""
echo "Generated files:"
echo "  - TOOLS.md"
echo "  - config/agents.json"
echo "  - MEMORY.md"
echo ""
echo "Still needs manual setup:"
echo "  - ~/.openclaw/openclaw.json  (OpenClaw gateway config)"
echo "  - API keys (ANTHROPIC_API_KEY, OPENAI_API_KEY in env)"
echo "  - MCP Agent Mail (~/mcp_agent_mail/)"
echo "  - Beads CLI (bd) — install from source"
echo "  - Truthsayer — install from source"
echo "  - Argus — install from source"
echo "  - systemd services (openclaw-gateway, mcp-agent-mail)"
echo ""
info "Run 'openclaw gateway start' to start the gateway."
