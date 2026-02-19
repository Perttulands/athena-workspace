# Migration to Chrote — Mercury Task List

_Tasks to run with Mercury on chrote (100.102.1.26) to prepare for Athena's move from the Hetzner VPS._

## Context

Athena currently runs on a Hetzner VPS (ahjo-1, 8GB RAM) as an OpenClaw bot. We're moving the entire operation — repos, tools, binaries, workspace, state — to your home Linux server (chrote). Mercury is already running there as a separate OpenClaw bot. Both will coexist using OpenClaw's `--profile` flag.

**After migration:**
- Mercury stays at `~/.openclaw/` on port 18500 (unchanged)
- Athena lives at `~/.openclaw-athena/` on port 18501
- All Agora repos, Go binaries, and assets live on chrote
- Telegram webhook points to chrote via Tailscale Funnel
- Hetzner VPS is decommissioned for Athena (kept for other uses)

---

## Phase 1: Prepare the environment

These steps get chrote ready to receive Athena's files.

### 1.1 Install Go toolchain

**Why:** Athena's tools (truthsayer, oathkeeper, relay, bd) are Go binaries. The Go compiler isn't on chrote yet — only `gopls` and `blogwatcher` are in `~/go/bin/`. We need the full toolchain to build/update these tools later.

```bash
wget https://go.dev/dl/go1.26.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
rm go1.26.0.linux-amd64.tar.gz
```

Verify: `/usr/local/go/bin/go version` → `go1.26.0`

### 1.2 Add PATH entries

**Why:** Go binaries, the Go toolchain, and npm global packages all need to be findable. Mercury might already have some of these — check first, add what's missing.

Add to `~/.bashrc` (or `~/.profile`):
```bash
export PATH="$HOME/go/bin:/usr/local/go/bin:$HOME/.npm-global/bin:$PATH"
```

Then `source ~/.bashrc` and verify:
- `which go` → `/usr/local/go/bin/go`
- `which bd` → should work after Phase 2

### 1.3 Create directories for Athena's repos

**Why:** The rsync from VPS will create these, but having them ready avoids permission issues.

```bash
mkdir -p ~/athena ~/argus ~/truthsayer ~/oathkeeper ~/relay
mkdir -p ~/learning-loop ~/ludus-magnus ~/agent-agora ~/athena-web
mkdir -p ~/Agora ~/gws-agent-factory ~/moonshot-research
```

---

## Phase 2: Receive files from VPS

**Why:** This is the actual migration. Run from the VPS side (Athena runs `migrate-to-chrote.sh`). Mercury just needs to be aware it's happening.

### 2.1 Dry run first

_Athena runs from VPS:_
```bash
~/athena/scripts/migrate-to-chrote.sh --dry-run
```

Mercury: check that nothing looks like it would overwrite your stuff. Key safety: OpenClaw state goes to `~/.openclaw-athena/`, NOT `~/.openclaw/`.

### 2.2 Full sync

_Athena runs from VPS:_
```bash
~/athena/scripts/migrate-to-chrote.sh
```

This transfers:
- All Agora repos (~300MB core, ~2.5GB total with projects)
- Go binaries: `bd`, `truthsayer`, `oathkeeper`, `relay`, `ntm` → `~/go/bin/`
- OpenClaw state → `~/.openclaw-athena/` (memory, sessions, agent configs)
- Agora assets (images, music) → `~/Agora/`

### 2.3 Verify binaries work

```bash
bd --version          # expect: 0.46.0
truthsayer --help     # should print usage
oathkeeper --help     # should print usage
relay --help          # should print usage
```

---

## Phase 3: Set up Athena's OpenClaw profile

**Why:** Athena needs her own OpenClaw instance, isolated from Mercury. The `--profile` flag creates a separate config directory and state.

### 3.1 Initialize the profile

```bash
openclaw --profile athena setup
```

This creates `~/.openclaw-athena/` if it doesn't exist already. The rsync in Phase 2 already put memory and session files there — setup will create any missing structure.

### 3.2 Run onboarding

```bash
openclaw --profile athena onboard
```

This will ask for:
- **Anthropic API key** — for Claude (Athena's main model)
- **OpenAI API key** — for Codex dispatch
- **Telegram bot token** — Athena's bot token (same one as on VPS)
- **Telegram webhook URL** — will be set up in Phase 4

### 3.3 Copy workspace files

**Why:** Athena's personality, memory, and operating rules need to be in the profile's workspace.

The rsync should have placed these in `~/.openclaw-athena/`. Verify these exist:
```bash
ls ~/.openclaw-athena/SOUL.md
ls ~/.openclaw-athena/IDENTITY.md
ls ~/.openclaw-athena/USER.md
ls ~/.openclaw-athena/TOOLS.md
ls ~/.openclaw-athena/MEMORY.md
ls ~/.openclaw-athena/AGENTS.md
```

### 3.4 Update TOOLS.md

**Why:** TOOLS.md references the old VPS hostname and IPs. Needs to reflect chrote.

Edit `~/.openclaw-athena/TOOLS.md`:
- Change host from `ahjo-1-ubuntu-8gb-hel1` to `chrote`
- Update Tailscale IP from `100.103.188.87` to `100.102.1.26`
- Update any port references (gateway → 18501)
- Update user from `perttu` to `chrote` (or whatever the OS user is)

---

## Phase 4: Network — Tailscale Funnel

**Why:** Telegram sends webhook updates to a public URL. The VPS had a public IP. Chrote is behind NAT. Tailscale Funnel exposes a port through Tailscale's infrastructure — no router config, no open ports.

### 4.1 Enable Funnel for Athena's port

```bash
tailscale funnel 18501
```

This gives you a URL like `https://chrote.tail-xxxxx.ts.net:18501/`

### 4.2 Update Telegram webhook

Use the funnel URL as the webhook endpoint for Athena's Telegram bot:
```bash
curl "https://api.telegram.org/bot<ATHENA_BOT_TOKEN>/setWebhook?url=https://chrote.tail-xxxxx.ts.net:18501/telegram/webhook"
```

(Exact webhook path depends on OpenClaw's config — check `~/.openclaw-athena/openclaw.json`)

### 4.3 Verify webhook

Send a test message to Athena's Telegram bot. It should arrive at chrote's OpenClaw instance on port 18501.

---

## Phase 5: Start Athena

### 5.1 Test run (foreground)

```bash
openclaw --profile athena gateway --port 18501
```

Check logs for errors. Send a Telegram message, verify response.

### 5.2 Set up as systemd service (persistent)

**Why:** So Athena survives reboots and restarts automatically.

Create `/etc/systemd/system/openclaw-athena.service`:
```ini
[Unit]
Description=OpenClaw Gateway (Athena)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=chrote
ExecStart=/usr/bin/openclaw --profile athena gateway --port 18501
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-athena
sudo systemctl status openclaw-athena
```

### 5.3 (Optional) Athena Web

If you want the dashboard:
```bash
# Check if athena-web service file was copied, update paths, then:
sudo systemctl enable --now athena-web
curl http://localhost:9000
```

---

## Phase 6: Cron and automation

### 6.1 Merge cron entries

**Why:** Chrote already has its own cron. Don't replace — merge Athena's entries.

Review VPS cron (saved during migration):
```bash
cat /tmp/ahjo-crontab.txt
```

Currently just one entry:
```
30 5 * * 1 ~/athena/scripts/doc-governance-weekly.sh >> ~/athena/state/logs/doc-governance-weekly.log 2>&1
```

Add to chrote's crontab:
```bash
crontab -e
# Add Athena's entries at the bottom
```

### 6.2 Argus

Argus monitors infrastructure. It may need config updates for chrote (different services, ports, paths). Review `~/argus/` config before enabling.

---

## Phase 7: Verify everything end-to-end

```bash
# Tools
bd --version                              # 0.46.0
bd list                                    # should show beads
truthsayer scan ~/athena/scripts/          # should scan
oathkeeper --help                          # should print usage

# OpenClaw
openclaw --profile athena status           # running on 18501
# Send Telegram message → get response

# Git
cd ~/athena && git status                  # clean, remotes intact
cd ~/truthsayer && git remote -v           # points to GitHub

# Services
curl http://localhost:18501                # athena gateway
curl http://localhost:9000                 # athena-web (if enabled)
```

---

## Phase 8: Decommission VPS (Athena only)

**Why:** Once everything works on chrote, stop Athena on the VPS. Keep the VPS running for other uses if needed.

_On VPS (ahjo-1):_
```bash
sudo systemctl stop openclaw-gateway
sudo systemctl disable openclaw-gateway
# Optionally stop athena-web too
```

Don't delete files yet — keep them as backup for a week.

---

## Summary

| What | Where on chrote |
|------|----------------|
| Mercury (existing) | `~/.openclaw/` port 18500 |
| Athena (new) | `~/.openclaw-athena/` port 18501 |
| Agora repos | `~/athena/`, `~/argus/`, etc. |
| Go binaries | `~/go/bin/` (bd, truthsayer, oathkeeper, relay, ntm) |
| Go toolchain | `/usr/local/go/` |
| Assets | `~/Agora/` |
| Telegram webhook | Tailscale Funnel → port 18501 |
