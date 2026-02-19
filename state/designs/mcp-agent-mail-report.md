# MCP Agent Mail: Comprehensive Analysis Report

**Report for:** Athena (Swarm Coordinator)
**Date:** 2026-02-14
**Codebase:** `mcp_agent_mail` v0.3.0 (Alpha), MIT License
**Source:** `$HOME/mcp_agent_mail-wt-bd-2eq` (branch `bead-bd-2eq`)

---

## 1. What MCP Agent Mail Actually IS

### One-sentence summary

A mail-like asynchronous coordination server for AI coding agents, exposed as an HTTP-only FastMCP server, backed by SQLite (for queries) and Git (for human-auditable archives).

### Architecture

```
Agents (Claude Code, Codex, Gemini, Cursor, Cline, Windsurf, etc.)
    |
    | HTTP (Streamable HTTP transport, port 8765, bearer token auth)
    |
    v
FastMCP Server (app.py, ~11K lines)
    |
    +-- SQLite + FTS5 (aiosqlite, SQLModel/SQLAlchemy async)
    |     - agents, messages, message_recipients, file_reservations
    |     - agent_links, window_identities, message_summaries
    |     - products, product_project_links
    |     - Full-text search via FTS5 with external content triggers
    |
    +-- Git Archive (GitPython, one repo per project)
    |     - messages/YYYY/MM/<id>.md (canonical + frontmatter)
    |     - agents/<name>/inbox/YYYY/MM/<id>.md (per-recipient copies)
    |     - agents/<name>/outbox/YYYY/MM/<id>.md (sender copy)
    |     - agents/<name>/profile.json
    |     - file_reservations/<sha1>.json
    |     - attachments/<xx>/<sha1>.webp
    |
    +-- Web UI (Jinja2 templates, server-rendered HTML at /mail)
    |
    +-- LLM integration (LiteLLM, for thread summarization + project sibling detection)
```

### Core concepts

- **Projects**: Identified by absolute directory path (the agent's working directory). Two agents in the same path = same project. Slug is derived deterministically.
- **Agent identities**: Memorable adjective+noun names (e.g., "GreenCastle", "BlueMountain"). Persist across session restarts via window identity or re-registration.
- **Messages**: GitHub-Flavored Markdown with frontmatter. Support to/cc/bcc, threading via `thread_id`, importance levels (normal/high/urgent), acknowledgment tracking, and inline image attachments (auto-converted to WebP).
- **File reservations**: Advisory time-limited leases on file paths/globs. Can be exclusive or shared. Optional pre-commit guard blocks commits that conflict with active exclusive reservations.
- **Contact policies**: Agents can set open/auto/contacts_only/block_all. Cross-project messaging requires explicit contact handshake (`request_contact`/`respond_contact`).

### Key technical decisions

- **HTTP-only**: No SSE, no STDIO. Streamable HTTP is the forward-compatible MCP transport.
- **Dual persistence**: Git for human auditability, SQLite for fast queries. Every message exists in both.
- **Commit queue**: Batches multiple git commits to reduce lock contention under concurrency.
- **Per-project archive locks**: `SoftFileLock` (filelock library) serializes archive mutations per project. Process-level `asyncio.Lock` prevents re-entrant acquisition.
- **EMFILE recovery**: Automatic retry for safe/idempotent tools when OS file descriptor limits are hit.

### File layout (source)

| File | Purpose |
|------|---------|
| `app.py` (~11K LOC) | Core server: all MCP tools, resources, `build_mcp_server()` factory |
| `models.py` | SQLModel data models (Project, Agent, Message, FileReservation, AgentLink, WindowIdentity, MessageSummary, Product, etc.) |
| `config.py` | Settings via python-decouple, frozen dataclasses for HttpSettings, DatabaseSettings, StorageSettings, LlmSettings, ToolFilterSettings, etc. |
| `storage.py` | Git archive helpers, commit queue, attachment processing, file locks, image conversion |
| `db.py` | SQLAlchemy async engine init, session factory, schema migration, query tracking |
| `guard.py` | Pre-commit/pre-push guard installation, chain-runner script generation |
| `http.py` | FastAPI/ASGI HTTP app, Web UI routes, bearer auth middleware, RBAC, rate limiting |
| `llm.py` | LiteLLM wrapper for thread summarization and project sibling suggestions |
| `cli.py` | Typer CLI: server management, guard install/uninstall, archive save/restore, share export, config commands |
| `share.py` | Static mailbox export pipeline (snapshot, scrub, sign, encrypt, bundle) |
| `utils.py` | Name generation (adjective+noun lists), slugification, validation |
| `rich_logger.py` | Rich-formatted tool call logging with panels and spinners |

---

## 2. Tools and Resources Exposed

### MCP Tools (37 total, organized by cluster)

#### Infrastructure (3)
| Tool | Description |
|------|-------------|
| `health_check` | Readiness probe: returns status, environment, HTTP binding, DB URL |
| `ensure_project` | Idempotently create/ensure project by absolute path |
| `install_precommit_guard` | Install pre-commit hook that blocks conflicting file reservations |
| `uninstall_precommit_guard` | Remove the pre-commit guard |

#### Identity (5)
| Tool | Description |
|------|-------------|
| `register_agent` | Register agent identity (program, model, task) in a project |
| `whois` | Lookup single agent profile |
| `create_agent_identity` | Create identity with optional name hint |
| `list_window_identities` | List window-based persistent identities |
| `rename_window` | Rename a window identity |
| `expire_window` | Expire/deactivate a window identity |

#### Messaging (6)
| Tool | Description |
|------|-------------|
| `send_message` | Send GFM message to agents (to/cc/bcc, threading, importance, acks, attachments) |
| `reply_message` | Reply to existing message in-thread |
| `fetch_inbox` | Fetch recent messages for an agent (with filtering) |
| `fetch_topic` | Fetch messages by topic |
| `mark_message_read` | Mark a message as read |
| `acknowledge_message` | Acknowledge receipt of a message |

#### Contact Management (4)
| Tool | Description |
|------|-------------|
| `request_contact` | Request cross-project contact link |
| `respond_contact` | Accept/reject contact request |
| `list_contacts` | List agent's contact links |
| `set_contact_policy` | Set contact policy (open/auto/contacts_only/block_all) |

#### Search & Summarization (4)
| Tool | Description |
|------|-------------|
| `search_messages` | FTS5 search over messages (subject/body, bm25 scoring) |
| `summarize_thread` | LLM-powered thread summarization |
| `summarize_recent` | Summarize recent activity across project |
| `fetch_summary` | Retrieve cached summaries |

#### File Reservations (4)
| Tool | Description |
|------|-------------|
| `file_reservation_paths` | Request advisory leases on paths/globs (exclusive or shared, with TTL) |
| `release_file_reservations` | Release held reservations |
| `force_release_file_reservation` | Admin force-release of another agent's reservation |
| `renew_file_reservations` | Extend TTL of active reservations |

#### Workflow Macros (4)
| Tool | Description |
|------|-------------|
| `macro_start_session` | Bundles: ensure_project + register_agent + fetch_inbox |
| `macro_prepare_thread` | Set up a threaded conversation |
| `macro_file_reservation_cycle` | Reserve, work, release cycle |
| `macro_contact_handshake` | Bidirectional contact link setup |

#### Build Slots (3, conditional)
| Tool | Description |
|------|-------------|
| `acquire_build_slot` | Acquire exclusive build slot for long-running tasks |
| `renew_build_slot` | Extend build slot TTL |
| `release_build_slot` | Release build slot |

#### Product Bus (5, conditional)
| Tool | Description |
|------|-------------|
| `ensure_product` | Create/ensure a product grouping |
| `products_link` | Link a project to a product |
| `search_messages_product` | Search across all projects in a product |
| `fetch_inbox_product` | Fetch inbox across product |
| `summarize_thread_product` | Summarize thread across product |

### MCP Resources (20+)

| Resource URI | Description |
|-------------|-------------|
| `resource://config/environment` | Server configuration snapshot |
| `resource://identity/{project}` | Identity mode, repo facts, worktree info |
| `resource://tooling/directory` | Full tool directory with metadata, clusters, capabilities |
| `resource://tooling/schemas` | JSON schemas for all tools |
| `resource://tooling/metrics` | Tool call/error counts |
| `resource://tooling/locks` | Active lock status |
| `resource://tooling/capabilities/{agent}` | Per-agent capability report |
| `resource://tooling/recent/{window_seconds}` | Recent tool usage |
| `resource://projects` | List all projects |
| `resource://project/{slug}` | Single project details |
| `resource://agents/{project_key}` | List agents in project |
| `resource://file_reservations/{slug}` | Active file reservations |
| `resource://message/{message_id}` | Single message detail |
| `resource://thread/{thread_id}` | Thread messages |
| `resource://mailbox/{agent}` | Agent mailbox (inbox) |
| `resource://outbox/{agent}` | Agent outbox |
| `resource://product/{key}` | Product details |
| `resource://views/urgent-unread/{agent}` | Urgent unread messages |
| `resource://views/ack-required/{agent}` | Messages needing acknowledgment |
| `resource://views/acks-stale/{agent}` | Stale acknowledgments |
| `resource://views/ack-overdue/{agent}` | Overdue acknowledgments |

### Tool Filtering

The server supports profile-based tool filtering to reduce context overhead:
- `full`: All tools (default)
- `core`: Identity + Messaging + File Reservations + Macros
- `minimal`: Just health_check, ensure_project, register_agent, send_message, fetch_inbox, acknowledge_message
- `messaging`: Identity + Messaging + Contact
- `custom`: User-defined include/exclude lists

Set via `TOOLS_FILTER_ENABLED=true` and `TOOLS_FILTER_PROFILE=<name>`.

---

## 3. How Agents Currently Use It

### MCP Configuration Files

Six config files exist for different agent clients. All point to `http://127.0.0.1:8765/api/` with bearer token auth:

| File | Client | Notes |
|------|--------|-------|
| `.mcp.json` | Claude Code | Canonical config |
| `codex.mcp.json` | OpenAI Codex | Identical structure |
| `cursor.mcp.json` | Cursor IDE | Identical structure |
| `cline.mcp.json` | Cline | Adds advisory `note` field |
| `windsurf.mcp.json` | Windsurf (Codeium) | Adds advisory `note` field |
| `gemini.mcp.json` | Google Gemini | **Different**: uses `httpUrl` instead of `url`, omits `type` field |

All configs use the same protocol: HTTP transport with a bearer token header. The Gemini config is the only structural outlier.

### Typical Agent Workflow

From SKILL.md and AGENTS.md, the recommended workflow is:

1. **Start session**: `macro_start_session(project_key=<cwd>, program="claude-code", model="opus-4.6")`
2. **Reserve files**: `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)`
3. **Announce work**: `send_message(project_key, agent_name, to=["OtherAgent"], subject="Starting refactor", thread_id="bd-123")`
4. **Check inbox periodically**: `fetch_inbox(project_key, agent_name)`
5. **Release when done**: `release_file_reservations(project_key, agent_name, paths=["src/**"])`

### Beads Integration

MCP Agent Mail integrates with the Beads task tracker:
- Beads issue ID (`bd-123`) = Mail thread ID
- Mail subject prefix: `[bd-123]`
- File reservation reason: `bd-123`
- `bd ready` picks work, Agent Mail coordinates execution

---

## 4. PLAN_TO_NON_DISRUPTIVELY_INTEGRATE_WITH_THE_GIT_WORKTREE_APPROACH.md

### Summary

A 70KB plan for making MCP Agent Mail work correctly when agents operate in Git worktrees of the same repository. The problem: by default, project identity is tied to the absolute directory path. Two worktrees of the same repo get different project identities, breaking coordination.

### Key proposals (all opt-in behind `WORKTREES_ENABLED=1`):

1. **Portable Project Identity**: Instead of using directory paths as identity, use a precedence chain:
   - `.agent-mail-project-id` repo marker file (committed)
   - Normalized git remote URL (`origin`)
   - `git rev-parse --git-common-dir`
   - `git rev-parse --show-toplevel`
   - Directory path (current default)

   This lets worktrees/clones resolve to the same project.

2. **Product Bus**: Group multiple repos (frontend/backend/infra) under a `product_uid` for product-wide inbox/search.

3. **Composable Hooks**: Install a chain-runner that plays nice with Husky/lefthook/pre-commit frameworks instead of overwriting hooks.

4. **Git Pathspec Matching**: Use Git wildmatch semantics for file reservation matching, honoring `core.ignorecase`.

5. **Build Slots**: Prevent build interference (port conflicts, cache corruption) when multiple agents run dev servers in different worktrees.

6. **Identity Inspection Resource**: `resource://identity/{project}` returns repo root, branch, worktree name, identity mode, etc.

### Implementation status

Partially implemented as of 2025-11-10:
- `WORKTREES_ENABLED` config flag exists (default false)
- Identity modes (`git-remote`, `git-toplevel`, `git-common-dir`, `dir`) are coded but gated
- Guard installer respects the gate
- Identity inspection resource works
- Pre-push guard with correct STDIN parsing is implemented

---

## 5. PLAN_TO_ENABLE_EASY_AND_SECURE_SHARING_OF_AGENT_MAILBOX.md

### Summary

A 23KB plan for exporting MCP Agent Mail mailboxes as static, read-only web bundles suitable for hosting on GitHub Pages, Cloudflare Pages, etc.

### Key features:

1. **Export Pipeline**: CLI command (`share export`) that:
   - Snapshots the SQLite database (read-only, no mutations)
   - Scrubs sensitive data (ack markers, file reservations, tokens, secrets)
   - Packages as a static bundle with viewer assets

2. **Static Bundle**: Contains:
   - `mailbox.sqlite3` (scrubbed snapshot)
   - `manifest.json` (metadata, hashes, signing info)
   - `viewer/` (pre-built SPA that runs SQL queries in-browser via WASM)
   - `HOW_TO_DEPLOY.md` (auto-generated per hosting platform)
   - Optional `chunks/` for large databases

3. **Client-Side Runtime**: Three WASM SQLite engines tried in order:
   - `@sqlite.org/sqlite-wasm` with OPFS caching (fastest)
   - `sql.js-httpvfs` for zero-header static hosting
   - `absurd-sql` IndexedDB fallback
   - In-memory `sql.js` last resort

4. **Security Layer**:
   - SHA-256 integrity manifest
   - Ed25519 signatures for tamper evidence
   - Optional `age` encryption (passphrase or public-key)
   - Scrub presets (standard, strict) for data minimization

5. **Interactive Wizard**: `--interactive` flag prompts for project selection, redaction, encryption

### Implementation status

Substantially implemented as of 2025-11-05:
- CLI `share export` and `share preview` work
- Scrubbing, signing, and manifest generation work
- Deployment wizard auto-detects hosting platforms
- Interactive wizard collects settings before export

---

## 6. Could It Solve Concurrent Repo Access (Two Agents, One Repo, No Worktrees)?

### Honest assessment: Partially, with important caveats.

**What it CAN do:**
- **Signal intent**: File reservations let Agent A declare "I'm editing `src/api/*.py`" so Agent B knows to avoid those files. This is the core value proposition.
- **Coordinate turns**: Agents can use messages to negotiate who works on what. "I'm doing the auth refactor, you handle the tests."
- **Pre-commit guard**: The guard can block commits that conflict with another agent's active exclusive reservation, preventing the most destructive form of concurrent access (overwriting each other's changes).
- **Detect conflicts early**: Before touching a file, an agent can check file reservations to see if anyone else has claimed it.

**What it CANNOT do:**
- **Prevent git index/staging conflicts**: Two agents in the same worktree share one git index. If both stage and commit at the same time, you get `index.lock` errors or mixed-up commits. Agent Mail's file reservations are *advisory* -- they don't prevent actual filesystem access.
- **Prevent file write races**: Two agents can still open and write the same file simultaneously. Agent Mail warns about intent but doesn't hold POSIX locks on code files.
- **Replace worktrees for parallel work**: If two agents need to `git add`, `git commit`, or run `git diff` simultaneously, they WILL step on each other without worktrees. Agent Mail's commit queue is for its own internal git archive, not the code repo.
- **Enforce reservations at the OS level**: Reservations are advisory. A misbehaving agent can ignore them. The pre-commit guard is the only enforcement point, and it only fires at commit time.

**Bottom line**: Agent Mail makes concurrent same-repo access *safer by convention* (agents that follow the protocol won't step on each other), but it does NOT make it *safe by mechanism*. For truly concurrent work, you still need either:
- Git worktrees (different working directories, different git indexes)
- Strict turn-taking (only one agent active at a time)
- Agent Mail's reservations + discipline + the pre-commit guard as a safety net

Agent Mail is best understood as a **coordination protocol**, not a **concurrency control mechanism**. It's the email system that helps two people avoid scheduling the same meeting room, not the lock on the meeting room door.

---

## 7. What It's Good For vs. What It's Not Good For

### What it IS good for

1. **Multi-agent communication**: Agents can send structured messages to each other without using the human's token budget. Messages persist in Git for auditability.

2. **Intent signaling**: File reservations let agents declare what they plan to edit, reducing accidental conflicts. The pre-commit guard provides a real enforcement point.

3. **Human oversight**: The Web UI lets humans monitor agent activity, read conversations, and send high-priority "Human Overseer" messages to redirect agents.

4. **Audit trail**: Every message and reservation is committed to a Git repo with timestamps, creating a complete, searchable history of agent coordination.

5. **Cross-project coordination**: The contact system and product bus let agents working on related but separate repos (e.g., frontend + backend) communicate.

6. **Searchable history**: FTS5 search across all messages with subject/body scoring. LLM-powered thread summarization for catching up on long conversations.

7. **Agent interoperability**: Works with Claude Code, Codex, Cursor, Cline, Windsurf, Gemini -- any MCP-capable client. Same protocol for all.

8. **Pre-commit safety net**: The guard is a real, practical tool that prevents the most damaging concurrent access scenarios at commit time.

9. **Task-coordination integration**: Clean integration with Beads task tracker (thread IDs = task IDs, reservation reasons = task references).

10. **Static mailbox export**: Share agent conversation history as a static website with Ed25519 signing and optional encryption.

### What it is NOT good for

1. **OS-level file locking**: It cannot prevent two processes from writing the same file. Reservations are advisory.

2. **Git index concurrency**: It cannot solve the problem of two agents sharing one git index in one worktree. That requires worktrees or turn-taking.

3. **Real-time coordination**: It's asynchronous (poll-based). No push notifications to agents by default (notification signals exist but require filesystem watching). Agents must call `fetch_inbox` to check for messages.

4. **Lightweight deployments**: It's a substantial system (27 Python dependencies, SQLite + Git, HTTP server). Not appropriate if you just need two agents to share a flag.

5. **Replacing proper CI/CD**: It's not a build system, test runner, or deployment pipeline. Build slots help avoid port conflicts but don't manage builds.

6. **Enforcing agent behavior**: It relies on agents following the protocol. A rogue agent that ignores reservations and doesn't check its inbox gains no benefit and disrupts others.

7. **Sub-second coordination**: The polling model and git commit overhead (even with batching) mean coordination latency is measured in seconds, not milliseconds.

8. **Replacing worktrees**: For truly parallel git operations (concurrent commits, branches, staging), git worktrees remain necessary. Agent Mail helps coordinate *around* this problem but doesn't eliminate it.

---

## Summary for Athena

MCP Agent Mail is a mature (despite "Alpha" label), well-architected coordination server designed for multi-agent development workflows. Its core value is **asynchronous coordination via messaging and advisory file reservations**, backed by a dual Git+SQLite persistence model that gives both machine queryability and human auditability.

**For the swarm coordination use case**, it provides:
- Agent identity management and discovery
- Structured messaging with threading and acknowledgment
- Advisory file reservations with pre-commit enforcement
- Cross-project and cross-repo coordination via the product bus
- Human oversight via Web UI and overseer messages

**Its main limitations** are that it's advisory (not enforced at the OS level), asynchronous (poll-based), and cannot solve the fundamental git index contention problem that arises when two agents share one worktree.

The worktree integration plan (partially implemented) would make it significantly more useful for worktree-based setups by unifying project identity across worktrees of the same repo.
