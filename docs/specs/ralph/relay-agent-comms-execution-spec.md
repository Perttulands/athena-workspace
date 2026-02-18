---
feature_slug: relay-agent-comms
primary_bead: bd-tbd
status: draft
owner: athena
scope_paths:
  - scripts/dispatch.sh
  - scripts/lib/config.sh
  - config/agents.json
  - scripts/wake-gateway.sh
last_updated: 2026-02-18
source_of_truth: false
---
# Execution Spec: Relay — Agent-to-Agent Communication

> Status: Draft  
> Author: Athena (systems architect)  
> Date: 2026-02-16  
> Replaces: MCP Agent Mail (mcp_agent_mail 0.3.0)

---

## 1. Problem Statement

MCP Agent Mail is a 11K-line Python application with 36 MCP tools, SQLite + FTS5, a git archive layer, and a web UI. After 3 months of use, we've sent 25 messages, created 146 file reservations, and spent more time debugging SQLite locks and 269MB memory bloat than actually coordinating agents.

### What Failed

| Issue | Root Cause |
|-------|------------|
| SQLite `database is locked` under 3+ concurrent agents | Single-writer SQLite, even with WAL mode |
| Git index lock contention | Every message triggers `git add` + `git commit` |
| 269MB RSS after 3 days | GitPython repo cache, SQLite mmap, tool metrics in memory |
| 36 MCP tools polluting agent context | We use ~5 operations; 31 tools are dead weight |
| Python dependency chain (uvicorn, aiosqlite, fastmcp, GitPython, litellm, Pillow...) | Upstream designed for a different use case |
| No heartbeat/liveness detection | Agents can't tell if peers are alive |
| No way to inject slash commands | Athena can't tell agents to run `/verify` |
| HTTP-only wake mechanism | Brittle; no fallback if gateway is restarting |

### What We Actually Use

1. **Message passing** — "I'm starting work on X" / "Done with Y, here's the summary"
2. **File reservations** — "I'm editing `src/auth/**`, don't touch it"
3. **Wake signals** — "Hey Athena, agent finished, come check results"
4. **Agent identity** — "Who's alive? Who's working on what?"

That's it. Four operations. Everything else is unused.

---

## 2. Solution: Relay

A **Go CLI** (`relay`) that provides agent-to-agent communication using only the filesystem. No database, no external services, no daemon required.

### Design Principles

1. **Files are the database.** NDJSON append-only logs, atomic file creates, `flock` for brief appends.
2. **Crash-safe by construction.** Every write is either an atomic rename or a flock-guarded append. No transaction rollbacks needed.
3. **Zero coordination overhead.** No connection pools, no WAL checkpointing, no circuit breakers. Just files.
4. **CLI-first.** Every operation is a single command. Agents call `relay send`, not an HTTP API.
5. **Context-minimal.** Five commands cover 95% of use. No 36-tool MCP catalog.
6. **Daemon optional.** File-based operations work without any running process. Optional daemon adds pub/sub notifications.

---

## 3. Architecture

### 3.1 Storage Layout

```
~/.relay/
├── agents/
│   ├── athena/
│   │   ├── inbox.jsonl          # Append-only NDJSON, one message per line
│   │   ├── meta.json            # Agent metadata (program, model, task, registered_at)
│   │   └── heartbeat            # Single line: ISO timestamp (atomic overwrite)
│   ├── agent-bd-42/
│   │   ├── inbox.jsonl
│   │   ├── meta.json
│   │   └── heartbeat
│   └── ...
├── reservations/
│   ├── {sha256-of-path}.json    # One file per active reservation (atomic create)
│   └── ...
├── commands/
│   ├── {ulid}.json              # Pending slash commands (atomic create, consumed by target)
│   └── ...
├── wake/
│   └── trigger                  # Touch file; inotify watcher picks up changes
├── global.jsonl                 # Append-only global event log (optional, for debugging)
└── relay.lock                   # PID file for optional daemon
```

### 3.2 Message Format (NDJSON)

Each line in `inbox.jsonl` is a self-contained JSON object:

```json
{
  "id": "01JMHF3XYZ...",
  "ts": "2026-02-16T06:08:00Z",
  "from": "agent-bd-42",
  "to": "athena",
  "subject": "Completed auth refactor",
  "body": "All tests pass. 3 files changed. Ready for review.",
  "thread": "bd-42",
  "priority": "normal",
  "tags": ["completion", "bd-42"]
}
```

**ID format**: [ULID](https://github.com/oklog/ulid) — lexicographically sortable, contains timestamp, no coordination needed.

**Priority levels**: `low`, `normal`, `high`, `urgent`

### 3.3 Reservation Format

Each reservation is a single file at `reservations/{hash}.json`:

```json
{
  "id": "01JMHF4ABC...",
  "agent": "agent-bd-42",
  "pattern": "src/auth/**",
  "repo": "$HOME/oathkeeper",
  "exclusive": true,
  "reason": "Implementing bd-42: auth refactor",
  "created_at": "2026-02-16T06:08:00Z",
  "expires_at": "2026-02-16T07:08:00Z"
}
```

**Hash key**: SHA-256 of `repo + ":" + pattern` — ensures one reservation per path pattern per repo.

**Conflict detection**: Before creating, scan existing reservations for overlapping patterns. Glob overlap detection handles `src/auth/**` vs `src/auth/login.go`.

### 3.4 Command Format

Slash commands are fire-and-forget files:

```json
{
  "id": "01JMHF5DEF...",
  "ts": "2026-02-16T06:08:00Z",
  "from": "agent-bd-42",
  "target_session": "agent:main:main",
  "command": "/verify",
  "args": "oathkeeper bd-42",
  "status": "pending"
}
```

The target session (OpenClaw or another agent) polls or watches the `commands/` directory.

### 3.5 Concurrency Model

| Operation | Mechanism | Contention Window |
|-----------|-----------|-------------------|
| Send message (append to inbox) | `flock(LOCK_EX)` on `inbox.jsonl.lock` | ~microseconds (single line write) |
| Create reservation | `O_CREAT\|O_EXCL` (atomic create, fails if exists) | Zero (kernel-level atomicity) |
| Release reservation | `os.Remove()` | Zero |
| Update heartbeat | Write to temp file + `rename()` | Zero (atomic rename) |
| Read inbox | No lock needed (readers don't interfere with append) | Zero |
| Read reservations | `readdir` + read each file | Zero (read-only) |

**Why this can't lock**: `flock` is held only for the duration of a single `write()` syscall (~microseconds for one NDJSON line). Even 100 concurrent agents would serialize appends in <1ms total. This is fundamentally different from SQLite, which holds write locks across entire transactions.

**Why this can't lose messages**: Append under `flock` is atomic. If the process crashes mid-write, the worst case is a partial last line, which is detectable (invalid JSON) and recoverable (truncate to last valid line).

### 3.6 Wake Mechanisms (Layered)

Relay provides three wake mechanisms, tried in order:

```
┌─────────────────────────────────────────────────┐
│ 1. OpenClaw callGateway (Node.js, via wake-gateway.sh)  │ ← Primary
├─────────────────────────────────────────────────┤
│ 2. Unix domain socket (direct to gateway)       │ ← Fast, no Node.js
├─────────────────────────────────────────────────┤
│ 3. Touch ~/.relay/wake/trigger (inotify)        │ ← Always works
└─────────────────────────────────────────────────┘
```

1. **callGateway** (current method): Invoke `wake-gateway.sh`. Reliable when gateway is running.
2. **Unix socket**: Relay speaks the gateway's internal protocol directly. No Node.js process spawn. Requires discovering the gateway socket path from OpenClaw config.
3. **File trigger**: Touch `~/.relay/wake/trigger`. A lightweight watcher (systemd path unit or inotifywait loop) detects the change and calls the gateway. **Always works**, even if the gateway is temporarily down — the wake queues until the watcher restarts.

The `relay wake` command tries all three in order, succeeding on the first that works.

---

## 4. CLI Interface

### 4.1 Command Reference

```
relay — Agent-to-agent communication

COMMANDS:
  relay send <to> <message>           Send a message to an agent's inbox
  relay read [flags]                  Read messages from your inbox
  relay reserve <pattern> [flags]     Reserve file paths
  relay release <pattern>             Release a file reservation
  relay reservations [flags]          List active reservations
  relay wake [text]                   Wake Athena (OpenClaw gateway)
  relay cmd <session> <command>       Inject a slash command into a session
  relay status                        Show all agents, heartbeats, reservations
  relay register <name> [flags]       Register agent identity
  relay heartbeat                     Update agent heartbeat
  relay gc                            Clean up expired reservations and stale agents
  relay daemon                        Run optional notification daemon
  relay version                       Print version

GLOBAL FLAGS:
  --agent <name>     Agent identity (default: $RELAY_AGENT or hostname)
  --dir <path>       Data directory (default: ~/.relay)
  --json             Output as JSON (for scripting)
  --quiet            Suppress non-essential output
```

### 4.2 Detailed Command Specs

#### `relay send`

```bash
relay send <to> <message> [flags]

FLAGS:
  --subject <text>     Message subject (default: first 80 chars of body)
  --thread <id>        Thread ID (e.g., bead ID)
  --priority <level>   low|normal|high|urgent (default: normal)
  --tag <tag>          Add tag (repeatable)
  --broadcast          Send to ALL registered agents
  --wake               Also wake Athena after sending

EXAMPLES:
  relay send athena "Bead bd-42 complete. All tests pass."
  relay send athena "Need review" --thread bd-42 --priority high --wake
  relay send --broadcast "Rebasing main, hold commits for 2 minutes" --priority urgent
```

**Behavior**: Appends one NDJSON line to `~/.relay/agents/<to>/inbox.jsonl` under flock. If `--broadcast`, appends to every registered agent's inbox. If `--wake`, calls `relay wake` after sending.

#### `relay read`

```bash
relay read [flags]

FLAGS:
  --from <agent>       Filter by sender
  --thread <id>        Filter by thread
  --since <duration>   Only messages newer than (e.g., "1h", "30m", "2026-02-16")
  --unread             Only messages not yet marked read (via cursor file)
  --last <n>           Last N messages (default: 20)
  --tail               Follow mode: print new messages as they arrive (inotify)
  --mark-read          Mark displayed messages as read

EXAMPLES:
  relay read --unread
  relay read --from agent-bd-42 --thread bd-42
  relay read --since 1h --json
  relay read --tail                    # Live follow
```

**Behavior**: Reads own `inbox.jsonl`, applies filters, outputs formatted text or JSON. Read cursor stored in `~/.relay/agents/<self>/cursor` (byte offset into inbox file).

**Tail mode**: Uses `inotify` (Linux) to watch the inbox file for appends. Prints new messages as they arrive. Useful for long-running agents that need to react to messages.

#### `relay reserve`

```bash
relay reserve <pattern> [flags]

FLAGS:
  --repo <path>        Repository path (default: current directory)
  --shared             Shared reservation (multiple agents can hold)
  --ttl <duration>     Time-to-live (default: "1h")
  --reason <text>      Reason for reservation
  --force              Override existing reservation (even exclusive)
  --check              Dry run: report conflicts without reserving

EXAMPLES:
  relay reserve "src/auth/**" --repo $HOME/oathkeeper --reason "bd-42 auth refactor"
  relay reserve "*.go" --shared --ttl 2h
  relay reserve "README.md" --check    # Just check for conflicts
```

**Behavior**: Creates `~/.relay/reservations/{hash}.json` atomically. Before creating, scans existing reservation files for overlapping patterns. Reports conflicts and fails unless `--force`.

**Glob overlap detection**: Uses `doublestar`-compatible matching. `src/auth/**` overlaps with `src/auth/login.go` and `src/**`. Exact algorithm: a reservation A conflicts with B if any concrete path could match both A's and B's patterns.

#### `relay release`

```bash
relay release <pattern> [flags]

FLAGS:
  --repo <path>        Repository path (default: current directory)
  --all                Release ALL reservations held by this agent

EXAMPLES:
  relay release "src/auth/**"
  relay release --all
```

**Behavior**: Removes the reservation file. Only the owning agent can release (unless `--force` on reserve was used to override).

#### `relay reservations`

```bash
relay reservations [flags]

FLAGS:
  --repo <path>        Filter by repository
  --agent <name>       Filter by agent
  --expired            Include expired reservations

EXAMPLES:
  relay reservations
  relay reservations --repo $HOME/oathkeeper --json
```

**Behavior**: Lists all `~/.relay/reservations/*.json` files, parses and displays. Checks expiry timestamps.

#### `relay wake`

```bash
relay wake [text] [flags]

FLAGS:
  --method <m>         Force specific method: gateway|socket|file (default: auto)

EXAMPLES:
  relay wake "Agent bd-42 completed. Check results."
  relay wake --method file "Agent done"
```

**Behavior**: Tries wake methods in priority order (§3.6). Returns success on first successful wake. Logs which method succeeded.

#### `relay cmd`

```bash
relay cmd <target-session> <command> [args...] [flags]

FLAGS:
  --wait <duration>    Wait for command to be consumed (poll the file)
  --wake               Wake Athena after posting command

EXAMPLES:
  relay cmd agent:main:main "/verify oathkeeper bd-42"
  relay cmd agent:main:main "/status" --wake
```

**Behavior**: Creates `~/.relay/commands/{ulid}.json` atomically. The target session's integration polls or watches this directory. Commands include a `status` field that transitions: `pending` → `consumed` → `done`.

**OpenClaw integration**: Athena's heartbeat or a file watcher picks up pending commands from `~/.relay/commands/` and injects them into the appropriate session.

#### `relay status`

```bash
relay status [flags]

FLAGS:
  --agents             Show only agents
  --reservations       Show only reservations
  --commands           Show only pending commands
  --stale <duration>   Heartbeat age threshold for "stale" (default: "5m")

EXAMPLES:
  relay status
  relay status --json
```

**Output example**:
```
AGENTS (3 alive, 1 stale)
  athena           alive   last heartbeat: 12s ago    task: orchestrator
  agent-bd-42      alive   last heartbeat: 45s ago    task: auth refactor
  agent-bd-43      alive   last heartbeat: 2m ago     task: API endpoints
  agent-bd-40      STALE   last heartbeat: 47m ago    task: (unknown)

RESERVATIONS (4 active, 1 expired)
  src/auth/**          agent-bd-42   exclusive   expires in 42m   oathkeeper
  src/api/routes.go    agent-bd-43   exclusive   expires in 1h    oathkeeper
  tests/**             agent-bd-42   shared      expires in 42m   oathkeeper
  README.md            agent-bd-40   exclusive   EXPIRED 12m ago  oathkeeper

PENDING COMMANDS (1)
  01JMHF5DEF...   agent-bd-42 → agent:main:main   /verify oathkeeper bd-42   2m ago
```

#### `relay register`

```bash
relay register <name> [flags]

FLAGS:
  --program <text>     Agent program (e.g., "claude-code", "codex")
  --model <text>       Model name (e.g., "opus", "gpt-5.3-codex")
  --task <text>        Current task description
  --bead <id>          Associated bead ID

EXAMPLES:
  relay register agent-bd-42 --program claude-code --model opus --task "Auth refactor" --bead bd-42
```

**Behavior**: Creates `~/.relay/agents/<name>/meta.json` (atomic write via rename). Also writes initial heartbeat.

#### `relay heartbeat`

```bash
relay heartbeat [flags]

FLAGS:
  --task <text>        Update task description in meta.json

EXAMPLES:
  relay heartbeat
  relay heartbeat --task "Now working on tests"
```

**Behavior**: Overwrites `~/.relay/agents/<self>/heartbeat` with current ISO timestamp via atomic rename. Optionally updates `meta.json` task field.

#### `relay gc`

```bash
relay gc [flags]

FLAGS:
  --expired-only       Only clean expired reservations (don't touch stale agents)
  --stale <duration>   Agent stale threshold (default: "30m")
  --dry-run            Show what would be cleaned without doing it

EXAMPLES:
  relay gc
  relay gc --dry-run
```

**Behavior**: Removes expired reservation files. Optionally archives stale agent directories (moves heartbeat to `heartbeat.stale`). Truncates consumed command files older than 1 hour.

---

## 5. Integration Points

### 5.1 dispatch.sh Integration

Replace the MCP Agent Mail coordination block in dispatch.sh:

**Before** (current):
```bash
# Coordination Instructions
- Use MCP Agent Mail to register yourself, check file reservations...
```

**After**:
```bash
# In runner script, before agent starts:
relay register "$SESSION_NAME" --program "$AGENT_TYPE" --model "$MODEL" --task "$PROMPT_TRUNCATED" --bead "$BEAD_ID"
relay reserve <files-from-prompt> --repo "$REPO_PATH" --reason "bead $BEAD_ID" --ttl "${WATCH_TIMEOUT_SECONDS}s"

# In runner script, heartbeat loop (background):
while true; do relay heartbeat; sleep 60; done &

# In runner script, on completion:
relay release --all
relay send athena "Bead $BEAD_ID complete" --thread "$BEAD_ID" --priority high --wake
```

Agent prompt coordination section becomes:
```
## Coordination
- Run `relay reservations --repo .` to see what files are claimed
- Run `relay read --unread` to check for messages from other agents
- Run `relay send <agent> "<message>"` to communicate
- Run `relay reserve "<pattern>"` before editing files
```

### 5.2 OpenClaw Gateway Integration

**Slash command consumption**: Add a file watcher (or poll in heartbeat) that:
1. Scans `~/.relay/commands/` for files where `target_session` matches
2. Parses the command
3. Injects it into the OpenClaw session
4. Updates the command file status to `consumed`

**Wake file watcher** (systemd path unit):
```ini
# ~/.config/systemd/user/relay-wake.path
[Path]
PathModified=$HOME/.relay/wake/trigger

[Install]
WantedBy=default.target
```
```ini
# ~/.config/systemd/user/relay-wake.service
[Service]
Type=oneshot
ExecStart=$HOME/athena/scripts/wake-gateway.sh "relay wake trigger"
```

### 5.3 Agent Prompt Context (Minimal)

Instead of 36 MCP tool descriptions consuming agent context, relay adds this to the prompt:

```
## Agent Communication (relay)
relay send <to> <msg>         — message another agent
relay read --unread           — check your inbox
relay reserve <pattern>       — claim files before editing
relay release --all           — release your reservations when done
relay status                  — see who's alive and what's reserved
```

Five lines. Not 36 tool schemas.

---

## 6. Optional Daemon Mode

For real-time notifications, relay can run an optional daemon:

```bash
relay daemon [flags]

FLAGS:
  --socket <path>      Unix socket path (default: /tmp/relay.sock)
  --gc-interval <dur>  GC interval (default: "5m")
```

### Daemon Capabilities

1. **Pub/sub notifications**: Agents connect to the Unix socket and subscribe to events (new messages, reservation changes). The daemon watches `~/.relay/` with inotify and pushes events.

2. **Automatic GC**: Runs `relay gc` periodically.

3. **Heartbeat monitor**: Detects stale agents and can send notifications.

4. **Command relay**: Watches `commands/` directory and pushes commands to connected sessions.

### Protocol (Unix socket, NDJSON)

```json
{"type":"subscribe","topics":["inbox","reservations","commands"]}
{"type":"event","topic":"inbox","agent":"agent-bd-42","message_id":"01JMHF3XYZ..."}
{"type":"event","topic":"reservation","action":"created","pattern":"src/auth/**"}
```

### Without Daemon

Everything works via polling / direct file operations. The daemon just adds push notifications. This is explicitly optional — the system must work perfectly without it.

---

## 7. Comparison: MCP Agent Mail vs Relay

| Dimension | MCP Agent Mail | Relay |
|-----------|---------------|-------|
| Language | Python (uvicorn + aiosqlite + GitPython + ...) | Go (single binary) |
| Storage | SQLite + FTS5 + Git archive | Filesystem (NDJSON + atomic files) |
| Binary size | ~50MB (Python venv) | ~5MB (Go static binary) |
| Memory | 269MB after 3 days | <5MB (no persistent state in process) |
| Concurrency | SQLite single-writer, retries + circuit breaker | flock (microsecond appends), atomic creates |
| Lock risk | Real (SQLite + git index) | Effectively zero (flock held <1ms) |
| Tools/commands | 36 MCP tools | 11 CLI commands |
| Context cost | ~4000 tokens (tool schemas) | ~200 tokens (5-line cheatsheet) |
| Dependencies | 15+ Python packages + system SQLite | Zero (static Go binary) |
| Transport | HTTP JSON-RPC only | CLI (filesystem) + optional Unix socket |
| Wake mechanism | HTTP only | 3 layers (callGateway + socket + file trigger) |
| Slash commands | Not supported | Native (`relay cmd`) |
| Agent liveness | Not supported | Heartbeat files (`relay heartbeat`) |
| Web UI | Yes (server-rendered HTML) | No (use `relay status --json` + jq) |
| FTS search | Yes (FTS5) | No (use grep on NDJSON — sufficient for our scale) |

---

## 8. Non-Goals

- **Web UI**: Not needed. Athena reads relay status via CLI. Perttu reads via Telegram.
- **Full-text search**: 25 messages in 3 months. `grep` works. If we hit 10K messages, revisit.
- **Cross-server communication**: All agents run on the same box. Filesystem is the transport.
- **Encryption**: All agents are trusted and local. No encryption needed.
- **Message persistence guarantees beyond filesystem**: If the disk dies, everything dies. That's fine.
- **Backward compatibility with MCP Agent Mail**: Clean break. No migration tool.
- **Contact policies / RBAC**: All agents in our system are trusted peers dispatched by Athena.
- **LLM-powered summaries**: Agents can summarize their own threads. No built-in LLM integration.

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| NDJSON file grows unbounded | Low (25 msgs/3 months) | Low | `relay gc` truncates old messages; rotate at 10MB |
| Glob overlap detection is imperfect | Medium | Low | Conservative: flag potential overlaps, let agent decide |
| Agent forgets to release reservations | High | Medium | TTL-based auto-expiry; `relay gc` cleans expired |
| Wake file trigger missed | Low | Medium | systemd path unit is reliable; retry touches |
| Agent crashes without cleanup | Medium | Medium | Heartbeat goes stale; `relay gc` cleans up |
| Concurrent glob pattern writes | Low | Low | Unique hash-based filenames; O_EXCL prevents duplicates |

---

## 10. Success Metrics

| Metric | Target | Current (MCP Agent Mail) |
|--------|--------|--------------------------|
| Time to send message | <10ms | ~200ms (HTTP + SQLite + Git) |
| Time to check reservations | <5ms | ~100ms (SQLite query) |
| Memory usage | <5MB | 269MB |
| Binary size | <10MB | ~50MB (Python venv) |
| Context tokens for agent prompt | <300 | ~4000 |
| Lock/contention errors | 0 | Occasional under load |
| Wake reliability | 99.9% | ~95% (HTTP only) |

---

## 11. Implementation Plan

### Sprint 1: Core (3–4 days)

Minimum viable relay: send, read, register, heartbeat, status.

- [ ] **US-001** — Project scaffolding: Go module, Makefile, CI lint+test, `.goreleaser.yml` for single static binary. Directory: `~/relay/`.
- [ ] **US-002** — Data directory initialization: `relay` auto-creates `~/.relay/{agents,reservations,commands,wake}` on first run. Configurable via `--dir` or `RELAY_DIR` env var.
- [ ] **US-003** — ULID generation: Import or vendor a ULID library (e.g., `oklog/ulid`). All IDs are ULIDs.
- [ ] **US-004** — `relay register <name>` — Create `~/.relay/agents/<name>/meta.json` via atomic temp+rename. Flags: `--program`, `--model`, `--task`, `--bead`. If agent dir exists, update meta.json (overwrite). Write initial heartbeat file.
- [ ] **US-005** — `relay heartbeat` — Atomic overwrite of `~/.relay/agents/<self>/heartbeat` with ISO timestamp. Optional `--task` updates meta.json too. Agent identity from `--agent` flag or `$RELAY_AGENT` env var.
- [ ] **US-006** — `relay send <to> <message>` — Append single NDJSON line to `~/.relay/agents/<to>/inbox.jsonl` under `flock(LOCK_EX)` on a `.lock` sidecar file. Generate ULID for message ID. Support `--subject`, `--thread`, `--priority`, `--tag`. Validate recipient exists (agent dir present). `--broadcast` iterates all agent dirs.
- [ ] **US-007** — `relay read` — Parse own `inbox.jsonl`, apply filters (`--from`, `--thread`, `--since`, `--last`), output formatted table or `--json`. `--unread` uses byte-offset cursor stored in `agents/<self>/cursor`. `--mark-read` advances cursor.
- [ ] **US-008** — `relay status` — Scan `agents/*/meta.json` + `agents/*/heartbeat`, scan `reservations/*.json`, scan `commands/*.json`. Output formatted summary. `--stale` flag configures heartbeat threshold. `--json` for machine output.
- [ ] **US-009** — `--json` and `--quiet` global flags wired through all commands. JSON output uses the same structures as the internal types (no separate serialization).
- [ ] **US-010** — Unit tests for: NDJSON append under concurrent goroutines (10+ writers), atomic file create, ULID ordering, message filtering, heartbeat staleness detection. Target: 80%+ coverage on core packages.

### Sprint 2: Reservations + Wake (2–3 days)

File reservations and reliable Athena wake.

- [ ] **US-011** — `relay reserve <pattern>` — Hash `repo:pattern` → SHA-256, create `reservations/{hash}.json` with `O_CREAT|O_EXCL`. Before creating, scan all reservation files for overlapping patterns. Report conflicts. Flags: `--repo` (default cwd), `--shared`, `--ttl` (default 1h), `--reason`, `--force`, `--check` (dry run).
- [ ] **US-012** — Glob overlap detection: Implement conservative overlap checker. Two patterns overlap if: (a) one is a prefix/superset of the other, or (b) they share a common concrete path. Use `doublestar` library for glob matching. Test cases: `src/**` vs `src/auth/login.go`, `*.go` vs `src/main.go`, `src/a/*` vs `src/b/*` (no overlap).
- [ ] **US-013** — `relay release <pattern>` — Remove matching reservation file. Verify caller is the owner (agent field in JSON matches `--agent`). `--all` releases all reservations for the calling agent.
- [ ] **US-014** — `relay reservations` — List all `reservations/*.json`, parse, display. Show expired status. Flags: `--repo`, `--agent`, `--expired`.
- [ ] **US-015** — `relay wake [text]` — Three-layer wake mechanism: (1) Execute `wake-gateway.sh` with the text. (2) If that fails, attempt direct Unix socket write to OpenClaw gateway (discover socket path from `~/.openclaw/openclaw.json`). (3) If that fails, touch `~/.relay/wake/trigger` and write the text to `~/.relay/wake/last-message`. Return which method succeeded.
- [ ] **US-016** — systemd path unit for wake file trigger: Write install script that creates `relay-wake.path` + `relay-wake.service` user units. Document manual setup in README.
- [ ] **US-017** — `relay gc` — Remove expired reservations. Archive stale agents (configurable threshold). Truncate consumed commands older than 1h. `--dry-run` mode. `--expired-only` skips stale agent cleanup.
- [ ] **US-018** — Integration tests: Full scenarios — register 3 agents, send messages, reserve files, check conflicts, release, gc cleanup. Run as Go test with temp directory.

### Sprint 3: Commands + Integration (2–3 days)

Slash command injection and dispatch.sh integration.

- [ ] **US-019** — `relay cmd <session> <command>` — Create `commands/{ulid}.json` atomically. Fields: `from`, `target_session`, `command`, `args`, `status: "pending"`, `ts`. `--wake` flag also wakes Athena.
- [ ] **US-020** — Command consumption protocol: Document the contract for command consumers. Consumer reads file, updates `status` to `"consumed"` (atomic rewrite), executes command, updates to `"done"`. Provide a Go helper function `ConsumeCommands(targetSession string) []Command` for embedding.
- [ ] **US-021** — `relay read --tail` (follow mode) — Use `inotify` (via `fsnotify` library) to watch `inbox.jsonl` for writes. Print new lines as they arrive. Graceful shutdown on SIGINT.
- [ ] **US-022** — Update `dispatch.sh` — Replace MCP Agent Mail integration with relay commands. Add `relay register` + `relay heartbeat` loop to runner script. Add `relay send --wake` on completion. Update coordination instructions in agent prompt. Remove MCP Agent Mail references from `TOOLS.md`, `AGENTS.md`, prompt templates.
- [ ] **US-023** — Update `wake-gateway.sh` — Add relay wake file as fallback if callGateway fails.
- [ ] **US-024** — `relay send --wake` compound flag — After successful message append, invoke wake logic. Avoids agents needing two separate commands.
- [ ] **US-025** — Man page / `--help` documentation — Every command has thorough `--help` output. Write a README.md with examples for each command.

### Sprint 4: Daemon + Polish (2–3 days, optional)

Optional daemon for pub/sub, plus hardening.

- [ ] **US-026** — `relay daemon` — Lightweight daemon that watches `~/.relay/` with inotify. Listens on Unix socket (`/tmp/relay.sock`). Pushes NDJSON events to connected clients. Manages PID file at `~/.relay/relay.lock`.
- [ ] **US-027** — Daemon pub/sub protocol — Clients connect to Unix socket, send `{"type":"subscribe","topics":["inbox","reservations","commands"]}`. Daemon pushes events as NDJSON lines. Clients can disconnect at any time (daemon handles broken pipes gracefully).
- [ ] **US-028** — Daemon auto-GC — Run `gc` logic every 5 minutes within the daemon process. Configurable interval.
- [ ] **US-029** — Daemon heartbeat monitor — Detect agents whose heartbeat is older than threshold. Optionally send notification message or log warning.
- [ ] **US-030** — Log rotation — When `inbox.jsonl` exceeds 10MB, rotate to `inbox.jsonl.1` (keep 1 rotated file). Cursor file adjusts accordingly.
- [ ] **US-031** — `relay` added to TOOLS.md, agent dispatch config, and OpenClaw startup. systemd unit for optional daemon. Complete deprecation of MCP Agent Mail service.
- [ ] **US-032** — Stress test — 20 concurrent goroutines each sending 1000 messages to the same inbox. Verify zero message loss, no corruption, <1s total for all 20K messages. Benchmark reservation create/release cycle.

---

## 12. Migration Plan

### Phase 1: Build & Parallel Run (Sprint 1–2)

- Build relay binary, install at `/usr/local/bin/relay`
- Keep MCP Agent Mail running
- New dispatches use relay; old agents still use MCP Agent Mail
- Athena reads both systems during transition

### Phase 2: Cutover (Sprint 3)

- Update `dispatch.sh` to use relay exclusively
- Update agent prompt templates to reference relay
- Stop MCP Agent Mail service
- Update `TOOLS.md`, `AGENTS.md`

### Phase 3: Cleanup (Sprint 4)

- Remove `mcp-agent-mail` systemd service
- Archive `~/mcp_agent_mail/` directory
- Remove MCP Agent Mail references from all docs
- Run `scripts/doc-gardener.sh` to catch stragglers

---

## 13. Open Questions

1. **Global event log**: Should `global.jsonl` log ALL events (messages, reservations, commands, heartbeats) for debugging, or is per-agent inbox sufficient? **Recommendation**: Yes, log everything. It's one append per event, cheap, and invaluable for debugging multi-agent scenarios.

2. **Inbox compaction**: When an agent's inbox gets large, should we compact (remove read messages) or just rotate? **Recommendation**: Rotate at 10MB. Compaction requires rewriting the file, which is more complex. At our message volume, rotation will happen approximately never.

3. **Cross-session command injection**: How does Athena actually inject a slash command from a `commands/*.json` file into an OpenClaw session? **Recommendation**: OpenClaw hook or heartbeat script that polls `~/.relay/commands/` and uses the OpenClaw internal API to inject. This is an OpenClaw integration point, not a relay concern.

4. **Reservation inheritance**: When `dispatch.sh` reserves files for an agent, should the agent be able to narrow its own reservations? **Recommendation**: Yes. The dispatch script reserves broad patterns; the agent can release and re-reserve more specific ones.

5. **Gateway socket discovery**: Can we reliably find the OpenClaw gateway's Unix socket path? **Recommendation**: Parse `~/.openclaw/openclaw.json` for the socket path. If not found, skip the socket wake method and fall through to file trigger.

---

## Appendix A: Why Not X?

| Alternative | Why Not |
|-------------|---------|
| Redis | External dependency. Overkill for <100 messages/day. |
| etcd / Consul | Massive external dependency for key-value storage we can do with files. |
| SQLite (done right) | Still single-writer. We don't need queries — we need appends and reads. |
| BoltDB / BadgerDB | Embedded KV stores add complexity. Files are simpler and inspectable. |
| gRPC | Requires a running server. We want CLI-first, daemon-optional. |
| NATS / RabbitMQ | Message brokers for distributed systems. We're on one box. |
| Shared memory / mmap | Complex, crash-unsafe, not inspectable. Files are debuggable with `cat`. |

## Appendix B: File System Guarantees We Rely On

1. **`rename()` is atomic on Linux ext4/xfs** — Used for meta.json and heartbeat updates.
2. **`O_CREAT|O_EXCL` is atomic** — Used for reservation creation. Kernel guarantees exactly one creator succeeds.
3. **`flock(LOCK_EX)` + `write()` + `flock(LOCK_UN)` serializes appends** — Used for inbox writes. Lock held only during the write syscall.
4. **`readdir()` is consistent** — Used for scanning reservations and commands. May miss files being created concurrently, but that's acceptable (next scan picks them up).
5. **Partial writes are detectable** — A crash mid-append leaves a partial JSON line. On read, the last line that doesn't parse as JSON is discarded. No silent corruption.

## Appendix C: Estimated Binary Size Budget

| Component | Estimated Size |
|-----------|---------------|
| Go runtime | ~2MB |
| CLI framework (cobra) | ~500KB |
| ULID library | ~50KB |
| fsnotify (inotify) | ~100KB |
| doublestar (glob) | ~50KB |
| Application code | ~500KB |
| **Total (stripped, UPX)** | **~3–5MB** |
