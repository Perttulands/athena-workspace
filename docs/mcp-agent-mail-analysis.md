# MCP Agent Mail — Comprehensive Analysis

> Produced: 2026-02-16  
> Version analyzed: 0.3.0 (local clone at `/home/perttu/mcp_agent_mail/`)  
> Upstream: https://github.com/Dicklesworthstone/mcp_agent_mail  
> Author: Dicklesworthstone (Jeff Emmanuel)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [API Reference — Tools & Resources](#2-api-reference)
3. [Database Schema & SQLite Usage](#3-database-schema)
4. [Known Issues & Failure Modes](#4-known-issues)
5. [Configuration Options](#5-configuration)
6. [Multi-Agent Coordination Model](#6-coordination-model)
7. [Recommendations for Our Setup](#7-recommendations)

---

## 1. Architecture Overview

### What It Is

MCP Agent Mail is a **mail-like coordination layer** for AI coding agents. It exposes an HTTP-only [FastMCP](https://github.com/jlowin/fastmcp) server that provides:

- **Agent identities** — memorable adjective+noun names (e.g., "GreenCastle")
- **Messaging** — threaded GFM messages with importance levels, acknowledgments, attachments
- **File reservations** — advisory locks on file paths/globs to signal editing intent
- **Contact policies** — per-agent controls on who can message whom
- **Search** — FTS5-powered full-text search across message history
- **Web UI** — human-facing mail viewer at `/mail`

### Core Design: Dual Persistence

```
Agents ──HTTP/MCP──▶ FastMCP Server
                         │
                    ┌────┴────┐
                    ▼         ▼
              Git Archive   SQLite+FTS5
              (audit)       (queries)
```

1. **SQLite** (`storage.sqlite3`) — fast indexing, queries, FTS5 search, file reservation management
2. **Git repository** (`~/.mcp_agent_mail_git_mailbox_repo/`) — human-auditable Markdown artifacts:
   - `projects/{slug}/agents/{name}/profile.json` — agent profiles
   - `projects/{slug}/agents/{name}/inbox/YYYY/MM/*.md` — inbox copies
   - `projects/{slug}/agents/{name}/outbox/YYYY/MM/*.md` — outbox copies
   - `projects/{slug}/messages/YYYY/MM/*.md` — canonical messages
   - `projects/{slug}/messages/threads/{thread_id}.md` — thread digests
   - `projects/{slug}/file_reservations/*.json` — reservation artifacts
   - `projects/{slug}/attachments/xx/{sha1}.webp` — image attachments

### Transport Layer

- **HTTP-only** FastMCP (Streamable HTTP). No SSE, no STDIO.
- Single endpoint at `/api/` accepting JSON-RPC POST requests
- Bearer token authentication (static token from `.env`)
- Optional JWT/JWKS authentication with RBAC roles
- Token-bucket rate limiting (memory or Redis backend)
- Web UI at `/mail` routes (server-rendered HTML)

### Process Model

Runs as a single Python process via uvicorn:
```
uv run python -m mcp_agent_mail.cli serve-http --host 127.0.0.1 --port 8765
```

Background tasks within the process handle:
- File reservation cleanup (expired leases)
- ACK TTL monitoring (overdue acknowledgments)
- Tool metrics emission
- Retention/quota reporting
- FD health monitoring (prevents EMFILE cascades)

### Key Dependencies

| Package | Purpose |
|---------|---------|
| `fastmcp >=2.10.5` | MCP protocol server |
| `fastapi` | HTTP framework |
| `uvicorn` | ASGI server |
| `sqlmodel` + `sqlalchemy[asyncio]` + `aiosqlite` | Async SQLite ORM |
| `GitPython` | Git archive operations |
| `filelock` | Cross-platform file locking |
| `litellm` | LLM integration for summaries |
| `pillow` | Image processing (WebP conversion) |
| `pathspec` | Gitignore-style path matching |
| `authlib` | JWT verification |

---

## 2. API Reference

### MCP Tools (36 tools)

#### Infrastructure / Setup
| Tool | Description |
|------|-------------|
| `health_check` | Server readiness + live DB check, circuit breaker state, pool stats |
| `ensure_project` | Create or find project by human key (absolute path) |
| `install_precommit_guard` | Install git pre-commit hook enforcing file reservations |
| `uninstall_precommit_guard` | Remove the pre-commit guard |

#### Identity
| Tool | Description |
|------|-------------|
| `register_agent` | Register agent identity in a project (name, program, model, task) |
| `create_agent_identity` | Create identity with auto-generated name |
| `whois` | Look up agent details (program, model, task, last active, reservations) |
| `list_window_identities` | List persistent window-based identities for a project |
| `rename_window` | Rename a window identity |
| `expire_window` | Expire a window identity |

#### Messaging
| Tool | Description |
|------|-------------|
| `send_message` | Send GFM message to recipients with importance, threading, attachments, ack_required |
| `reply_message` | Reply to a specific message (inherits thread) |
| `fetch_inbox` | Fetch inbox for an agent (paginated, filterable by importance/thread) |
| `fetch_topic` | Fetch messages by broadcast topic |
| `mark_message_read` | Mark a message as read |
| `acknowledge_message` | Acknowledge a message (with optional reply) |

#### Contact Management
| Tool | Description |
|------|-------------|
| `request_contact` | Request cross-project contact link |
| `respond_contact` | Approve/block a pending contact request |
| `list_contacts` | List all contact links for an agent |
| `set_contact_policy` | Set agent's contact policy (open/auto/contacts_only/block_all) |

#### Search & Summarization
| Tool | Description |
|------|-------------|
| `search_messages` | FTS5 full-text search with scope/order/boost controls |
| `summarize_thread` | LLM-powered thread summarization |
| `summarize_recent` | Summarize recent project activity (with LLM) |
| `fetch_summary` | Retrieve stored summaries |

#### File Reservations
| Tool | Description |
|------|-------------|
| `file_reservation_paths` | Reserve file paths/globs (exclusive or shared, with TTL) |
| `release_file_reservations` | Release held reservations |
| `force_release_file_reservation` | Force-release another agent's reservation |
| `renew_file_reservations` | Extend TTL on existing reservations |

#### Build Slots
| Tool | Description |
|------|-------------|
| `acquire_build_slot` | Reserve a build/CI slot (prevents parallel builds) |
| `renew_build_slot` | Extend build slot TTL |
| `release_build_slot` | Release build slot |

#### Product Bus (Cross-Repo)
| Tool | Description |
|------|-------------|
| `ensure_product` | Create logical product grouping |
| `products_link` | Link project to product |
| `search_messages_product` | Search across all projects in a product |
| `fetch_inbox_product` | Fetch inbox across product projects |
| `summarize_thread_product` | Summarize thread across product |

#### Workflow Macros
| Tool | Description |
|------|-------------|
| `macro_start_session` | One-call bootstrap: ensure project + register + reserve files + fetch inbox |
| `macro_prepare_thread` | Create/resume thread with initial message |
| `macro_file_reservation_cycle` | Reserve → work → release cycle |
| `macro_contact_handshake` | Request + auto-respond contact link |

### MCP Resources (20+ resources)

| URI Pattern | Description |
|-------------|-------------|
| `resource://config/environment` | Server configuration summary |
| `resource://tooling/directory` | Tool directory with clusters, complexity, descriptions |
| `resource://tooling/schemas` | JSON schemas for all tools |
| `resource://tooling/metrics` | Tool call/error metrics |
| `resource://tooling/locks` | Active archive lock status |
| `resource://tooling/capabilities/{agent}` | Agent capability mapping |
| `resource://tooling/recent/{window_seconds}` | Recent tool usage within time window |
| `resource://projects` | List all projects |
| `resource://project/{slug}` | Project details |
| `resource://agents/{project_key}` | List agents in project |
| `resource://identity/{project}` | Identity resource for project |
| `resource://file_reservations/{slug}` | File reservations for project |
| `resource://message/{message_id}` | Single message detail |
| `resource://thread/{thread_id}` | Thread messages with optional bodies |
| `resource://mailbox/{agent}` | Agent mailbox (inbox) |
| `resource://outbox/{agent}` | Agent outbox |
| `resource://product/{key}` | Product details with linked projects |
| `resource://views/urgent-unread/{agent}` | Urgent unread messages |
| `resource://views/ack-required/{agent}` | Messages awaiting acknowledgment |
| `resource://views/acks-stale/{agent}` | Stale (overdue) acknowledgments |
| `resource://views/ack-overdue/{agent}` | ACK overdue messages |

### HTTP Routes (Web UI + Health)

| Route | Description |
|-------|-------------|
| `GET /health/liveness` | Basic liveness (always 200) |
| `GET /health/readiness` | Full readiness with DB check + circuit breaker |
| `POST /api/` | MCP JSON-RPC endpoint |
| `GET /mail` | Unified inbox dashboard |
| `GET /mail/projects` | Projects index |
| `GET /mail/{project}` | Project overview + search + agents |
| `GET /mail/{project}/inbox/{agent}` | Agent inbox |
| `GET /mail/{project}/message/{id}` | Message detail |
| `GET /mail/{project}/search` | Dedicated search page |
| `GET /mail/{project}/file_reservations` | File reservations list |
| `GET /mail/{project}/attachments` | Messages with attachments |
| `GET /mail/{project}/overseer/compose` | Human Overseer message composer |
| `GET /mail/unified-inbox` | Cross-project activity |

---

## 3. Database Schema & SQLite Usage

### Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `projects` | Project registry | id, slug (unique), human_key, created_at |
| `agents` | Agent identities | id, project_id (FK), name (unique per project), program, model, task_description, contact_policy |
| `messages` | All messages | id, project_id, sender_id, thread_id, topic, subject, body_md, importance, ack_required, created_ts, attachments (JSON) |
| `message_recipients` | Recipient tracking | message_id + agent_id (composite PK), kind (to/cc/bcc), read_ts, ack_ts |
| `file_reservations` | Advisory file locks | id, project_id, agent_id, path_pattern, exclusive, reason, created_ts, expires_ts, released_ts |
| `agent_links` | Cross-project contacts | a/b project+agent pairs, status (pending/approved/blocked), expires_ts |
| `window_identities` | Terminal window identity persistence | project_id, window_uuid, display_name, expires_ts |
| `products` | Logical product groupings | product_uid (unique), name (unique) |
| `product_project_links` | Product↔Project M:N | product_id, project_id |
| `project_sibling_suggestions` | LLM-ranked sibling suggestions | project_a_id, project_b_id, score, status, rationale |
| `message_summaries` | Stored LLM summaries | project_id, summary_text, start_ts, end_ts, source_message_count, llm_model |
| `fts_messages` | FTS5 virtual table | message_id, subject, body |

### SQLite Configuration (PRAGMAs)

Set on every new connection via SQLAlchemy event listener:

```sql
PRAGMA journal_mode=WAL;          -- Write-Ahead Logging for concurrent reads
PRAGMA synchronous=NORMAL;        -- Faster than FULL, WAL provides crash safety
PRAGMA busy_timeout=60000;        -- 60s wait for locks
PRAGMA wal_autocheckpoint=1000;   -- Checkpoint every ~4MB
PRAGMA cache_size=-32768;         -- 32MB page cache
PRAGMA temp_store=MEMORY;         -- Temp tables in memory
PRAGMA mmap_size=268435456;       -- 256MB memory-mapped I/O
```

### Connection Pooling

- **Pool size**: 3 (base) + 4 (overflow) = 7 max connections
- **Pool timeout**: 45s
- **Pool recycle**: 3600s (1 hour)
- **Pool pre-ping**: enabled (detects stale connections)
- **Pool reset on return**: rollback (cleans uncommitted transactions)

### FTS5 Full-Text Search

- Virtual table `fts_messages` indexes `subject` and `body` columns
- Maintained via triggers on INSERT/UPDATE/DELETE of `messages` table
- Supports BM25 ranking when FTS5 is available
- Falls back to LIKE queries if FTS5 is not compiled in

### Performance Indexes

Extensive custom indexes beyond SQLAlchemy defaults:
- `idx_messages_created_ts` — chronological queries
- `idx_messages_thread_id` — thread lookups
- `idx_messages_importance` — priority filtering
- `idx_messages_sender_created` — outbox queries
- `idx_messages_project_created` — project-scoped chronological
- `idx_messages_project_topic` — topic-based queries
- `idx_file_reservations_expires_ts` — expiration cleanup
- `idx_file_reservations_project_released_expires` — active reservation queries
- Multiple `agent_links` indexes for contact lookups

### WAL Checkpointing Strategy

- **Auto-checkpoint**: Every 1000 pages (~4MB)
- **Periodic passive checkpoint**: Every 50th connection checkin (not every checkin to reduce overhead)
- **Passive mode**: Only checkpoints pages that can be checkpointed without waiting (no writer blocking)

---

## 4. Known Issues & Failure Modes

### 4.1 SQLite Locking (The Problem We Hit)

**Root cause**: SQLite allows only **one writer at a time**. Even with WAL mode, concurrent write operations must serialize. When multiple agents simultaneously:
- Send messages (writes to messages + message_recipients + FTS triggers)
- Create/release file reservations
- Register/update agents

...they can produce `"database is locked"` errors.

**Mitigations already in codebase**:

1. **`retry_on_db_lock` decorator** — Exponential backoff with jitter (7 retries, 0.05s base, up to 8s max delay). Catches `OperationalError` with lock-related messages.

2. **Circuit breaker** — After 5 consecutive failures, opens circuit for 30s (fail-fast to prevent cascading retries). States: CLOSED → OPEN → HALF_OPEN → CLOSED.

3. **60s busy_timeout** — SQLite-level wait before returning SQLITE_BUSY.

4. **Conservative pool** — Only 3+4=7 connections to prevent FD exhaustion.

5. **Passive WAL checkpointing** — Uses PASSIVE mode to avoid blocking writers during checkpoint.

**Why it can still fail**:

- Under sustained multi-agent load (3+ agents writing simultaneously), the retry budget (~6.35s total) can be exhausted
- Git archive commits hold file locks that further serialize operations
- The single-process architecture means all agents share one SQLite connection pool
- `aiosqlite` runs SQLite operations in a thread pool, but SQLite itself is the bottleneck

### 4.2 Git Index Lock Contention

Every message, agent profile, and file reservation write also triggers a git commit. Git uses `.git/index.lock` for atomic operations.

**Mitigations**:
- `GitIndexLockError` exception class with retry count
- `_try_clean_stale_git_lock()` — removes locks older than 300s
- Commit queue batches non-conflicting commits
- Per-project commit locks (`.commit.lock`) to avoid cross-project contention
- Exponential backoff on git index lock errors

**Remaining risk**: Under high concurrency, the commit queue + per-project locks + git index lock create a serial bottleneck. Each message send requires: DB write → archive write → git add → git commit.

### 4.3 File Descriptor Exhaustion (EMFILE)

GitPython opens file handles for each Repo object. Under heavy load:

**Mitigations**:
- LRU repo cache (max 16 repos, with eviction grace period)
- Repo semaphore (max 32 concurrent operations)
- `proactive_fd_cleanup()` when headroom drops below threshold
- Background FD health monitor (every 30s)
- EMFILE recovery: auto-retry after clearing repo cache for safe tools

### 4.4 File Lock Deadlocks

`AsyncFileLock` wraps `SoftFileLock` with metadata tracking and adaptive retries.

**Protections**:
- Re-entrant acquisition detection (raises `RuntimeError`)
- Process-level `asyncio.Lock` prevents same-process contention
- Stale lock cleanup (when owner PID is dead or lock age > 180s)
- Adaptive timeout strategy (short first attempt → progressively longer)

### 4.5 Memory Growth

At 269MB RSS after 3 days with moderate usage:
- Git Repo objects cached in memory
- LRU eviction with grace period means evicted repos linger
- FTS5 index data cached in process
- Tool metrics and recent usage tracking (`deque(maxlen=4096)`)

---

## 5. Configuration Options

All configuration via environment variables (`.env` file or shell). Loaded via `python-decouple`.

### HTTP Transport
| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_HOST` | `127.0.0.1` | Bind address |
| `HTTP_PORT` | `8765` | Listen port |
| `HTTP_PATH` | `/api/` | MCP endpoint path |
| `HTTP_BEARER_TOKEN` | *(empty)* | Static bearer token for auth |
| `HTTP_RATE_LIMIT_ENABLED` | `false` | Enable rate limiting |
| `HTTP_RATE_LIMIT_TOOLS_PER_MINUTE` | `60` | Tool calls per minute per IP |
| `HTTP_RATE_LIMIT_RESOURCES_PER_MINUTE` | `120` | Resource reads per minute per IP |
| `HTTP_RATE_LIMIT_BACKEND` | `memory` | `memory` or `redis` |
| `HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED` | `true` | Skip auth for localhost |

### JWT / RBAC
| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_JWT_ENABLED` | `false` | Enable JWT auth |
| `HTTP_JWT_ALGORITHMS` | `HS256` | JWT algorithms |
| `HTTP_JWT_SECRET` | *(empty)* | HMAC secret |
| `HTTP_JWT_JWKS_URL` | *(empty)* | JWKS URL for key discovery |
| `HTTP_RBAC_ENABLED` | `true` | Enable role-based access control |
| `HTTP_RBAC_DEFAULT_ROLE` | `reader` | Default role when no JWT |

### Database
| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite+aiosqlite:///./storage.sqlite3` | SQLAlchemy URL |
| `DATABASE_ECHO` | `false` | SQL echo logging |
| `DATABASE_POOL_SIZE` | *(auto: 3)* | Connection pool size |
| `DATABASE_MAX_OVERFLOW` | *(auto: 4)* | Max pool overflow |
| `DATABASE_POOL_TIMEOUT` | *(auto: 45)* | Pool wait timeout (seconds) |

### Storage / Git
| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_ROOT` | `~/.mcp_agent_mail_git_mailbox_repo` | Git archive root |
| `GIT_AUTHOR_NAME` | `mcp-agent` | Git commit author |
| `GIT_AUTHOR_EMAIL` | `mcp-agent@example.com` | Git commit email |
| `CONVERT_IMAGES` | `true` | Auto-convert images to WebP |
| `INLINE_IMAGE_MAX_BYTES` | `65536` | Max bytes before file storage |
| `ALLOW_ABSOLUTE_ATTACHMENT_PATHS` | `true` (dev) | Allow absolute paths for attachments |

### LLM Integration
| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_ENABLED` | `true` | Enable LLM features (summarization) |
| `LLM_DEFAULT_MODEL` | `gpt-4o-mini` | Default model for summaries |
| `LLM_TEMPERATURE` | `0.2` | Sampling temperature |
| `LLM_MAX_TOKENS` | `512` | Max output tokens |

### File Reservations
| Variable | Default | Description |
|----------|---------|-------------|
| `FILE_RESERVATIONS_CLEANUP_ENABLED` | `false` | Background cleanup of expired reservations |
| `FILE_RESERVATIONS_CLEANUP_INTERVAL_SECONDS` | `60` | Cleanup interval |
| `FILE_RESERVATIONS_ENFORCEMENT_ENABLED` | `true` | Enforce reservation conflicts |
| `FILE_RESERVATION_INACTIVITY_SECONDS` | `1800` | Inactivity timeout for reservations |

### ACK Tracking
| Variable | Default | Description |
|----------|---------|-------------|
| `ACK_TTL_ENABLED` | `false` | Enable ACK deadline monitoring |
| `ACK_TTL_SECONDS` | `1800` | ACK deadline (30 min) |
| `ACK_ESCALATION_ENABLED` | `false` | Auto-escalate overdue ACKs |
| `ACK_ESCALATION_MODE` | `log` | `log` or `file_reservation` |

### Tool Filtering
| Variable | Default | Description |
|----------|---------|-------------|
| `TOOLS_FILTER_ENABLED` | `false` | Enable tool filtering |
| `TOOLS_FILTER_PROFILE` | `full` | `full`, `core`, `minimal`, `messaging`, `custom` |

### Contact Policies
| Variable | Default | Description |
|----------|---------|-------------|
| `CONTACT_ENFORCEMENT_ENABLED` | `true` | Enforce contact policies on messaging |
| `CONTACT_AUTO_TTL_SECONDS` | `86400` | Auto-approved contact TTL |
| `MESSAGING_AUTO_REGISTER_RECIPIENTS` | `true` | Auto-register missing local recipients |
| `MESSAGING_AUTO_HANDSHAKE_ON_BLOCK` | `true` | Auto-handshake if delivery blocked |

### Agent Identity
| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_NAME_ENFORCEMENT_MODE` | `coerce` | `strict`, `coerce`, `always_auto` |
| `MCP_AGENT_MAIL_WINDOW_ID` | *(empty)* | Window UUID for persistent identity |

### Notifications
| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFICATIONS_ENABLED` | `false` | Enable file-based signal notifications |
| `NOTIFICATIONS_SIGNALS_DIR` | `~/.mcp_agent_mail/signals` | Signal file directory |

### Logging
| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Log level |
| `LOG_RICH_ENABLED` | `true` | Rich console formatting |
| `LOG_JSON_ENABLED` | `false` | JSON structured logging |
| `TOOLS_LOG_ENABLED` | `true` | Log tool calls with Rich panels |

---

## 6. Multi-Agent Coordination Model

### Intended Workflow

```
1. Each agent starts a session:
   macro_start_session(human_key="/path/to/project", program="claude-code", ...)
   → Returns: project info, agent name, inbox, active reservations

2. Before editing files:
   file_reservation_paths(project_key, agent_name, ["src/auth/**"], exclusive=true, ttl_seconds=3600)
   → Other agents see the reservation and choose different files

3. Communicate via threaded messages:
   send_message(project_key, agent_name, ["OtherAgent"], subject="API change", body_md="...", thread_id="FEAT-123")

4. Check inbox periodically:
   fetch_inbox(project_key, agent_name) → list of pending messages

5. Acknowledge important messages:
   acknowledge_message(project_key, agent_name, message_id, reply_body="Understood, adjusting...")

6. Release reservations when done:
   release_file_reservations(project_key, agent_name, ["src/auth/**"])
```

### Contact Policy Model

Agents have four contact policies:
- **`open`** — accept messages from anyone in the project
- **`auto`** (default) — allow if shared context exists (same thread, overlapping reservations, recent contact)
- **`contacts_only`** — require explicit contact approval (`request_contact` → `respond_contact`)
- **`block_all`** — reject all contacts

Cross-project communication requires an approved `AgentLink` (via `request_contact`/`respond_contact`).

### Integration with Beads

Designed to complement Beads task tracking:
- Beads owns task status/priority/dependencies
- Agent Mail carries conversations, decisions, and attachments
- Shared identifiers: Beads issue ID = Mail thread_id (e.g., `bd-123`)
- File reservation `reason` includes Beads issue ID

### Human Oversight

The **Human Overseer** feature lets humans send high-priority messages to agents via the web UI at `/mail/{project}/overseer/compose`. Messages include a preamble identifying them as human-originated.

---

## 7. Recommendations for Our Setup

### Current State Assessment

Our deployment:
- Running as systemd service on port 8765 (active 3+ days, 269MB RSS)
- 17 projects, 48 agents, 25 messages, 146 file reservations
- WAL mode active, no locking errors in recent logs
- Single `.env` with bearer token auth
- `TOOLS_LOG_ENABLED` is not set (defaults to `true` — verbose)

### 7.1 SQLite Locking — Fix vs Replace

**Assessment**: The codebase has extensive mitigations (retry with backoff, circuit breaker, WAL mode, passive checkpointing). Our current load (25 messages, moderate agent count) hasn't triggered locking issues recently. The risk increases with concurrent dispatch (3+ Codex agents writing simultaneously).

**Recommendation**: **Keep SQLite for now, tune settings, monitor**.

Specific tuning for our `.env`:
```bash
# Increase pool to handle burst from multiple agents
DATABASE_POOL_SIZE=5
DATABASE_MAX_OVERFLOW=8

# Enable cleanup to prevent stale reservations (we have 146!)
FILE_RESERVATIONS_CLEANUP_ENABLED=true
FILE_RESERVATIONS_CLEANUP_INTERVAL_SECONDS=120

# Enable health monitoring
INSTRUMENTATION_ENABLED=true
INSTRUMENTATION_SLOW_QUERY_MS=100
```

If we start hitting locking under heavy swarm load, the nuclear option is PostgreSQL (`asyncpg` is an optional dependency — `DATABASE_URL=postgresql+asyncpg://...`). The schema is SQLAlchemy-based and would work with PostgreSQL.

### 7.2 Reduce Noise

```bash
# Disable verbose tool logging (saves stdout/journal noise)
TOOLS_LOG_ENABLED=false
LOG_RICH_ENABLED=false

# OR use JSON logging for structured analysis
LOG_JSON_ENABLED=true
TOOLS_LOG_ENABLED=true
```

### 7.3 Tool Filtering

Our agents don't use build slots or product bus features. Reduce context overhead:
```bash
TOOLS_FILTER_ENABLED=true
TOOLS_FILTER_PROFILE=core
```
This exposes only: identity, messaging, file_reservations, workflow_macros, health_check, ensure_project — cutting ~70% of tool descriptions from context.

### 7.4 Notification Integration

Consider enabling file-based notifications for our dispatch system:
```bash
NOTIFICATIONS_ENABLED=true
NOTIFICATIONS_SIGNALS_DIR=~/.mcp_agent_mail/signals
```
Then `inotifywait` on signal files could trigger OpenClaw events when agents receive messages.

### 7.5 Git Archive Overhead

Every message sends triggers a git commit. For high-throughput scenarios:
- The commit queue batches non-conflicting commits (already in code)
- Consider if we actually need the git archive — it's an audit trail
- If not needed, a fork could disable git writes entirely (significant performance win)

### 7.6 Memory Management

At 269MB after 3 days, monitor for growth:
- Add `Restart=always` to systemd unit (currently `on-failure`)
- Consider weekly restart via timer
- The LRU repo cache (max 16) with 60s eviction grace is reasonable

### 7.7 Security

Current setup is reasonable for local-only (`127.0.0.1`):
- Bearer token auth active
- Localhost unauthenticated access allowed (default)
- No JWT/RBAC needed for single-server setup
- Web UI at `/mail` is accessible without auth when `HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true`

### 7.8 Fork vs Fix vs Replace Decision Matrix

| Option | Effort | Risk | Benefit |
|--------|--------|------|---------|
| **Keep as-is** | None | Medium (locking under heavy load) | Zero effort, working today |
| **Tune settings** | Low (30 min) | Low | Better performance, less noise |
| **Fork with SQLite fixes** | Medium (hours) | Low | Could disable git writes, optimize pool |
| **Fork with PostgreSQL** | Medium (hours) | Medium (new dependency) | Eliminates SQLite locking entirely |
| **Replace with custom solution** | High (days) | High | Purpose-built, but large effort |

**Recommended path**: **Tune settings now** (items 7.1–7.4 above). If we scale to 5+ concurrent agents and hit locking, **fork and add PostgreSQL option** or **disable git archive writes**.

### 7.9 Missing Features for Our Use Case

Things we might want that don't exist:
1. **Webhook callbacks** — no way to push notifications to OpenClaw when messages arrive (only file-based signals)
2. **Message expiry/cleanup** — retention reporting exists but no automatic deletion
3. **Agent heartbeats** — no built-in liveness detection for agents
4. **Priority queuing** — all messages are equal in delivery order (importance is metadata only)

---

## Appendix A: Our Current `.env`

```
HTTP_BEARER_TOKEN=<redacted>  (set)
```

All other settings use defaults. This means:
- Pool: 3+4=7 connections
- No cleanup workers running
- Tool logging enabled (verbose)
- LLM enabled but probably failing (no API keys in .env)
- Git archive at `~/.mcp_agent_mail_git_mailbox_repo/`

## Appendix B: Database Statistics (2026-02-16)

| Table | Row Count |
|-------|-----------|
| projects | 17 |
| agents | 48 |
| messages | 25 |
| message_recipients | 108 |
| file_reservations | 146 |
| agent_links | 96 |
| window_identities | 0 |
| products | 0 |

WAL status: journal_mode=wal, wal_pages=3 (healthy, fully checkpointed)

## Appendix C: Systemd Unit

```ini
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
User=perttu
WorkingDirectory=/home/perttu/mcp_agent_mail
EnvironmentFile=/home/perttu/mcp_agent_mail/.env
ExecStart=/home/perttu/.local/bin/uv run python -m mcp_agent_mail.cli serve-http --host 127.0.0.1 --port 8765
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
