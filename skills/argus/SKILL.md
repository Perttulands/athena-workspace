---
name: argus
description: Ops watchdog monitoring. Use when checking server health, investigating alerts, or understanding what Argus auto-detected.
---

# Argus

Independent ops watchdog (systemd service, 5-min loop). Uses Claude Haiku for reasoning.

## What It Monitors

- Services: openclaw-gateway, mcp-agent-mail status
- System: memory, disk, load, uptime
- Processes: orphan node --test, tmux sessions
- Agents: active tmux session counts

## What It Can Do (5 allowlisted actions)

1. restart_service (openclaw-gateway or mcp-agent-mail)
2. kill_pid (node/claude/codex processes only)
3. create_problem_bead (via `bd`)
4. send_alert (Telegram)
5. log_observation (state file)

Auto-creates problem beads when same issue recurs 3+ times.
Auto-kills orphan `node --test` processes after 3 detections.

## Checking Argus

```bash
sudo systemctl status argus          # Service status
journalctl -u argus --since "1h ago" # Recent logs
cat ~/argus/state/*.json             # State files
```
