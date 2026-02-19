# BOOTSTRAP.md — Setting Up the Agora

This guide is for agents (or humans) setting up the Agora system from scratch. Each component is independent and can be installed one at a time. Install what you need.

## Prerequisites

Before installing any component, ensure these are available:

```bash
# Required
git --version          # Git 2.x+
bash --version         # Bash 5.x+
curl --version         # For API calls and health checks
jq --version           # JSON processing

# For Go components (Beads, Oathkeeper, Truthsayer, Relay, Ludus Magnus)
go version             # Go 1.22+

# For Node components (Athena Web)
node --version         # Node 22+
npm --version
```

If Go is missing: `wget -qO- https://go.dev/dl/go1.23.0.linux-amd64.tar.gz | sudo tar -C /usr/local -xz` then add `/usr/local/go/bin` to PATH.

---

## 1. 🧵 Beads — Work Tracking

**What:** Distributed, git-backed work tracker. Created by Steve Yegge.  
**Needs:** Go

```bash
go install github.com/steveyegge/beads/cmd/bd@latest
bd version
```

**Verify:** `bd list` should return an empty list or existing beads.  
**Docs:** https://github.com/steveyegge/beads

---

## 2. 🔍 Truthsayer — Anti-Pattern Scanner

**What:** Scans code for anti-patterns. 88 rules, 5 languages.  
**Needs:** Go

```bash
git clone https://github.com/Perttulands/truthsayer.git
cd truthsayer
go install ./cmd/truthsayer/
```

**Verify:** `truthsayer scan .` should produce a report.  
**Docs:** https://github.com/Perttulands/truthsayer

---

## 3. ⚖️ Oathkeeper — Commitment Tracker

**What:** Scans agent transcripts for promises and tracks whether they were fulfilled.  
**Needs:** Go

```bash
git clone https://github.com/Perttulands/oathkeeper.git
cd oathkeeper
go install ./cmd/oathkeeper/
```

**Verify:** `oathkeeper --help` should show available commands.  
**Docs:** https://github.com/Perttulands/oathkeeper

---

## 4. 📡 Relay — Agent Messaging

**What:** Filesystem + HTTP message relay for inter-agent communication.  
**Needs:** Go

```bash
git clone https://github.com/Perttulands/relay.git
cd relay
go install ./cmd/relay/
```

**Verify:** `relay --help` should show available commands.  
**Docs:** https://github.com/Perttulands/relay

---

## 5. 🏟️ Ludus Magnus — Agent Training

**What:** Iterative prompt evolution. Train any agent through competition and selection.  
**Needs:** Go, an LLM API key (Anthropic recommended)

```bash
git clone https://github.com/Perttulands/ludus-magnus.git
cd ludus-magnus
go install ./cmd/ludus-magnus/
# or: make build (binary at ./bin/ludus-magnus)
```

**Verify:** `ludus-magnus --help` should show available commands.  
**Config:** Set `ANTHROPIC_API_KEY` in your environment.  
**Docs:** https://github.com/Perttulands/ludus-magnus

---

## 6. 👁️ Argus — Ops Watchdog

**What:** Autonomous monitoring service. Runs every 5 minutes, analyzes metrics, takes corrective action.  
**Needs:** Bash, curl, jq, systemd, an Anthropic API key, a Telegram bot token (for alerts)

```bash
git clone https://github.com/Perttulands/argus.git
cd argus
```

**Configure:**
1. Set your hostname in `prompt.md` (replace `<YOUR_HOSTNAME>`)
2. Create `.env` with:
   ```
   ANTHROPIC_API_KEY=sk-...
   TELEGRAM_BOT_TOKEN=...
   TELEGRAM_CHAT_ID=...
   ```
3. Install the systemd service:
   ```bash
   sudo cp deployment/argus.service /etc/systemd/system/
   sudo systemctl enable argus
   sudo systemctl start argus
   ```

**Verify:** `systemctl status argus` should show active.  
**Docs:** https://github.com/Perttulands/argus

---

## 7. 🏛️ Athena Web — Dashboard

**What:** Web portal showing agents, beads, and runs.  
**Needs:** Node.js 22+

```bash
git clone https://github.com/Perttulands/athena-web.git
cd athena-web
npm install
```

**Configure:**
1. Set port in environment or config (default: 9000)
2. Install as systemd service:
   ```bash
   sudo cp deployment/systemd/athena-web.service /etc/systemd/system/
   sudo systemctl enable athena-web
   sudo systemctl start athena-web
   ```

**Verify:** `curl http://localhost:9000` should return HTML.  
**Docs:** https://github.com/Perttulands/athena-web

---

## 8. ⚔️ Centurion — Test-Gated Merge

**What:** Script that runs tests before allowing merge to main.  
**Needs:** Already included in this workspace.

```bash
# No separate install — it's at scripts/centurion.sh
./scripts/centurion.sh merge <branch> <repo>
```

**Verify:** `./scripts/centurion.sh --help` or read the script header.

---

## 9. 🏛️ Athena Workspace — The Agora Itself

**What:** The command center. Templates, scripts, docs, and orchestration.  
**Needs:** All of the above (or whichever subset you want)

```bash
git clone https://github.com/Perttulands/athena-workspace.git
cd athena-workspace
```

**Configure:**
1. Write your own `USER.md` (who you are)
2. Write your own `SOUL.md` (who your agent is)
3. Write your own `IDENTITY.md` (agent name and voice)
4. Set agent models in `config/agents.json`
5. Set up [OpenClaw](https://github.com/openclaw/openclaw) as the gateway

---

## Environment Variables

These are needed across the system. Set them in your shell profile or `.env`:

```bash
# Required for LLM-powered components (Argus, Ludus Magnus)
ANTHROPIC_API_KEY=sk-ant-...

# Optional: for Argus Telegram alerts
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...

# Optional: for OpenAI-backed components
OPENAI_API_KEY=sk-...

# Go binaries
export PATH="$HOME/go/bin:/usr/local/go/bin:$PATH"
```

---

## Install Order (Recommended)

1. **Beads** — you'll use this immediately for tracking work
2. **Truthsayer** — catches problems early
3. **Athena Workspace** — the command center
4. **Argus** — start monitoring
5. **Everything else** — as needed

Each component works independently. You don't need all of them to start.
