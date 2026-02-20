---
name: relay
description: Agent-to-agent messaging via Relay. Use for sending messages, reading inboxes, reserving files, spawning agents, and checking swarm status.
---

# Relay

Agent messaging backbone. Handles inter-agent communication, file reservations, command routing, and agent lifecycle.

## Identity Resolution

All commands that act as "you" resolve agent identity in this order:

1. `--agent <name>` flag
2. `RELAY_AGENT` environment variable
3. Hostname fallback

## Core Commands

```bash
# Register yourself
relay register <name> [--program <p>] [--model <m>] [--task <t>] [--bead <b>]

# Messaging
relay send <to> <message> [--subject <s>] [--thread <t>] [--priority <p>] [--tag <t>] [--wake]
relay send --broadcast <message>       # Send to all agents (use sparingly)
relay read [--last N] [--from <agent>] [--since <duration>] [--unread] [--mark-read]
relay inbox                             # Alias for read
relay watch [--loop]                    # Block until new messages arrive

# File reservations (conflict prevention)
relay reserve <pattern> [--repo <path>] [--ttl <duration>] [--shared] [--reason <text>]
relay reserve <pattern> --check         # Check for conflicts without reserving
relay release <pattern> [--repo <path>]
relay release --all
relay reservations [--repo <path>] [--expired]

# Agent coordination
relay status [--stale <duration>]       # All agents, heartbeats, reservations
relay heartbeat [--task <text>]         # Update your heartbeat
relay cmd <session> <command> [args]    # Inject command into tmux session

# Spawning
relay spawn --repo <path> --agent <type> --prompt <text> [--title <t>] [--wait] [--notify <agent>]
# agent types: codex | claude:opus | claude:sonnet | claude:haiku

# Maintenance
relay gc [--stale <duration>] [--expired-only] [--dry-run]
```

## Global Flags

```
--agent <name>     Override agent identity
--dir <path>       Data directory (default: ~/.relay)
--json             Machine-readable JSON output
--quiet            Suppress non-essential output
```

## Typical Agent Workflow

```bash
# 1. Register on startup
relay register myagent --program claude --model opus --bead bd-abc

# 2. Reserve files you'll edit
relay reserve "src/auth/**" --reason "implementing login" --ttl 1h

# 3. Heartbeat periodically
relay heartbeat --task "writing auth module"

# 4. Signal completion
relay send athena "task complete" --wake
relay release --all
```

## Spawn (Dispatch Agent)

```bash
relay spawn \
  --repo /home/chrote/athena/tools/relay \
  --agent claude:sonnet \
  --prompt "Fix the bug in store.go" \
  --title "Fix store bug" \
  --wait \
  --notify athena
```

Creates a bead in workspace, runs `dispatch.sh`, optionally waits for result and notifies.

## Data Layout

```
~/.relay/
  agents/<name>/
    meta.json       # Agent registration
    heartbeat       # Last heartbeat timestamp
    inbox.jsonl     # Incoming messages (NDJSON)
    cursor          # Read position
  reservations/     # File reservation locks
  commands/         # Pending slash commands
  wake/             # Wake trigger files
```

## Go Client

```go
import "github.com/Perttulands/relay/pkg/client"

c, _ := client.NewClient("~/.relay")
c.Send("athena", "task complete")
msgs, _ := c.Read(client.ReadOpts{Last: 10})
watchMsgs, _ := c.Watch()  // blocks until new messages
```
