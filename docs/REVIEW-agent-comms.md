# Review: PRD-agent-comms.md (Relay)

> Reviewer: Senior systems engineer (subagent)  
> Date: 2026-02-16  
> Verdict: **Solid design with real gaps to fix before implementation**

---

## Executive Summary

The PRD correctly diagnoses the problem (MCP Agent Mail is massively over-engineered for what we use) and proposes a reasonable solution (filesystem-based CLI tool). The core architecture — NDJSON + flock + atomic rename — is sound for our scale. However, there are meaningful gaps in integration specifics, some over-engineering in the PRD itself, and several filesystem assumptions that need scrutiny.

**Bottom line**: Build it. But fix the issues below first, or you'll be debugging integration problems in Sprint 3 that should have been caught in design.

---

## 1. Architecture Gaps

### 1.1 Inbox read/write race with cursor (Real bug)

The `--unread` flag uses a byte-offset cursor in `agents/<self>/cursor`. A writer appends under flock on `inbox.jsonl.lock`. But the reader reads the inbox *without* holding that lock (§3.5 says "Readers don't interfere with append"). This is **almost** correct, but:

- Reader reads cursor offset, seeks to that offset, reads to EOF
- Writer appends a line concurrently
- Reader gets a **partial last line** (read happened mid-write)

On ext4, `write()` of a small buffer (<4KB, which NDJSON lines will be) to a file opened with `O_APPEND` is effectively atomic at the filesystem level. So in practice this is probably fine. But the PRD claims this explicitly ("readers don't interfere") without acknowledging that the guarantee comes from the kernel's pipe buffer atomicity for small writes, not from any lock. This should be documented: **relay read must tolerate and skip partial trailing lines**.

### 1.2 Broadcast under concurrent senders

`relay send --broadcast` iterates all agent dirs and appends to each inbox. If two agents broadcast simultaneously, they each acquire flocks on different inboxes in different orders. No deadlock risk (flock per file, not global), but broadcast is O(N) agents × O(flock acquisition). At 10 agents this is fine. At 50 it's slow. Document the expected agent count ceiling.

### 1.3 Command consumption is under-specified

§3.4 says commands transition `pending → consumed → done`. But the consumer does an "atomic rewrite" to update status. This means:
- Read the JSON file
- Modify the status field
- Write to temp + rename

Between read and rename, another process could also read the file and attempt to consume the same command. This is a classic TOCTOU race. **Fix**: Use `O_CREAT|O_EXCL` on a `.consumed` sidecar file as the claim mechanism, not rewriting the original. First process to create the sidecar wins.

### 1.4 No message ordering guarantee across agents

ULIDs are generated independently per process. Two agents sending messages at the "same" time will have ULIDs that are close but not causally ordered. This is fine for display but means you can't use ULID order as a happened-before relation. The PRD doesn't claim this, but it's worth a non-goal statement since someone will inevitably assume it.

### 1.5 Heartbeat doesn't detect zombie tmux sessions

The heartbeat loop in dispatch.sh (`while true; do relay heartbeat; sleep 60; done &`) runs as a background process **inside the runner script's tmux session**. If the agent process hangs (not crashes — hangs), the heartbeat loop keeps running, so the agent appears alive. The current dispatch.sh watcher already handles this via pane inspection, but relay's `status` command will show the agent as "alive" even when it's stuck. Not a showstopper, but the PRD's §3.5 implies heartbeats reliably indicate liveness. They indicate "the session is still running," not "the agent is making progress."

---

## 2. Missing Requirements

### 2.1 Codex agents run with full shell access (same as Claude Code)

**Correction (2026-02-16 audit):** Codex runs with `--yolo` (full access, no sandbox, no approval prompts). It has **identical shell capabilities to Claude Code** — arbitrary command execution, full filesystem access, network access, and can run any CLI tool. Both agents can run `relay reserve`, `relay read`, etc. directly. No special compatibility section is needed for Codex; the integration plan in §5.1 works for both agents equally.

### 2.2 No mention of how Athena reads relay

The PRD focuses on coding agents talking to each other and to Athena. But how does Athena (the OpenClaw main agent) actually read relay messages? Currently Athena uses MCP tools. With relay, Athena would need to:
- Run `relay read --unread` periodically (but AGENTS.md says "Never poll")
- Or use `relay read --tail` in a background process
- Or the daemon pushes events

The PRD doesn't specify which. This is a critical integration gap — the whole point of wake signals is to get Athena's attention, but what happens *after* Athena wakes up? Does the OpenClaw gateway integration automatically run `relay read`? This needs to be spelled out.

### 2.3 No error reporting back to sender

If `relay send <to> <message>` fails (recipient doesn't exist, disk full, flock timeout), the sender gets an exit code. But there's no mechanism for *asynchronous* failure notification. If Athena is down and 3 agents try `relay send athena --wake`, they succeed (message appended to inbox) but the wake fails. The `--wake` flag should clearly document that wake failure is non-fatal and the message is still delivered.

### 2.4 ralph.sh integration not mentioned

The PRD covers `dispatch.sh` integration but says nothing about `ralph.sh`. Ralph is a PRD execution loop that spawns fresh Claude/Codex sessions per iteration. If relay is the coordination mechanism, ralph.sh needs to:
- Register a persistent agent identity across iterations
- Not accumulate stale registrations (one per iteration)
- Handle the fact that each iteration is a fresh session that won't remember previous relay state

### 2.5 No inbox size management per-agent during active use

`relay gc` handles cleanup after the fact. But if an agent gets spammed by a buggy broadcast loop (not unlikely with autonomous agents), its inbox grows unboundedly during the session. There's no inbox size limit or backpressure. Low risk at current scale, but a `--max-inbox-size` or similar safety valve would be cheap to add.

---

## 3. Over-Engineering

### 3.1 The daemon (Sprint 4) — probably unnecessary

The daemon adds pub/sub over a Unix socket with NDJSON protocol. This is a mini message broker. For a system that sends 25 messages in 3 months, this is solving a problem that doesn't exist. `relay read --tail` with inotify gives you real-time notifications without a daemon. The systemd path unit for wake already covers the main "push" use case.

**Recommendation**: Cut Sprint 4 entirely. If you need it later, the architecture supports adding it. But building it now is premature.

### 3.2 Glob overlap detection (US-012) — over-scoped

"Two patterns overlap if any concrete path could match both" is computationally expensive and has edge cases (e.g., `**/*.go` vs `src/**` — overlap depends on directory structure). The PRD acknowledges this ("conservative: flag potential overlaps") but still specs a `doublestar`-compatible overlap checker.

**Simpler alternative**: Exact-match on the pattern string, plus a simple prefix check (`src/auth/**` conflicts with `src/auth/login.go` because one starts with the other's prefix minus the glob). Don't try to solve the general glob intersection problem. If two agents claim `*.go` and `src/main.go`, just flag it — let the agent decide.

### 3.3 Three-layer wake mechanism — two layers is enough

Layer 2 (Unix domain socket direct to gateway) requires reverse-engineering the OpenClaw gateway's internal protocol. The PRD says "discover socket path from openclaw.json" but openclaw.json (which I read) doesn't expose a socket path — it's HTTP on port 18500. This layer would require understanding undocumented OpenClaw internals.

**Recommendation**: Keep layers 1 (wake-gateway.sh) and 3 (file trigger + systemd path unit). Drop layer 2 unless OpenClaw documents a stable socket interface.

### 3.4 `relay cmd` — premature without a consumer

US-019 builds the command injection mechanism, but US-020 says the consumer is "documented contract" with a "Go helper function for embedding." Who embeds it? OpenClaw is Node.js. Unless someone writes an OpenClaw plugin or hook that polls `~/.relay/commands/`, the command injection feature has no consumer.

**Recommendation**: Don't build `relay cmd` until there's a concrete plan for the consumer side. Or scope it down: the consumer is a bash script that polls commands/ and pipes them into the OpenClaw CLI. Spec that script.

### 3.5 Global event log (§13, Open Question 1)

The PRD recommends logging ALL events to `global.jsonl`. At current volumes this is fine, but it duplicates data already present in per-agent inboxes and reservation files. More files to manage, more disk writes, marginal debugging value over `grep -r ~/.relay/`.

**Recommendation**: Skip it. If you need cross-agent event correlation, write a `relay log` command that merges and sorts from existing files.

---

## 4. Filesystem Assumptions

### 4.1 NDJSON + flock on ext4 — will it work?

**Yes, with caveats.**

The server runs ext4 on `/dev/sda1` (confirmed from `df` output). ext4 guarantees:
- `rename()` atomicity — ✅ used for meta.json, heartbeat
- `O_CREAT|O_EXCL` atomicity — ✅ used for reservations
- `flock()` advisory locking — ✅ used for inbox appends
- `write()` with `O_APPEND` for buffers < PIPE_BUF (4096 bytes) — effectively atomic on Linux

The concern is `flock` + `O_APPEND` for inbox writes. `flock` is advisory — any process that doesn't use flock can corrupt the file. This is safe as long as only relay writes to inbox files. If someone runs `echo "test" >> inbox.jsonl` directly, all bets are off. The PRD should note this assumption.

### 4.2 tmpfs consideration

The PRD doesn't mention tmpfs. For `~/.relay/` on ext4, every heartbeat update (every 60s per agent, 10 agents = 10 writes/minute) goes to disk. This is trivial load. However, if you wanted to reduce disk wear or improve latency, mounting `~/.relay/` on tmpfs would work — with the trade-off that all state is lost on reboot. Given that the state is ephemeral (heartbeats, live reservations, pending commands), tmpfs is actually a better fit than ext4 for most of this data.

**Recommendation**: Consider tmpfs for `~/.relay/` with a note that message history is lost on reboot (acceptable given the 25-messages-in-3-months volume). Or keep ext4 and don't worry about it — the I/O is negligible.

### 4.3 File count in reservations/

Each reservation is a file. With 10 agents × 5 reservations each = 50 files. `readdir()` on 50 files is instant. At 10,000 files (which would mean something has gone very wrong), ext4 with dir_index handles it fine. No issue here.

### 4.4 NDJSON line length

The PRD doesn't specify a maximum line length. If an agent sends a message with a 100KB body (e.g., a full file diff), that's one NDJSON line. `flock` + `write()` of 100KB is not atomic at the filesystem level (multiple write syscalls). The flock still protects it (other writers wait), but a crash mid-write of a large message could leave more than just "a partial last line" — it could leave a large amount of garbage.

**Recommendation**: Add a message body size limit (e.g., 64KB). For larger payloads, write to a sidecar file and reference it in the message.

---

## 5. Integration Concerns

### 5.1 dispatch.sh integration is the right approach but incomplete

The PRD's §5.1 shows the integration pattern. But dispatch.sh currently builds coordination context via `build_coordination_context()` which scans `state/runs/*.json`. With relay, this should instead call `relay status --json` and parse the output. The PRD doesn't mention this — it only shows the runner script changes, not the dispatch.sh pre-launch changes.

Also: the heartbeat loop (`while true; do relay heartbeat; sleep 60; done &`) needs to be killed on completion. The runner script's `emit_status` trap doesn't kill background jobs. This will leave orphan heartbeat processes. **Fix**: Store the heartbeat loop PID and kill it in the trap.

### 5.2 ralph.sh needs its own integration pattern

ralph.sh runs `run_model()` in a loop, each iteration being a fresh Claude/Codex invocation. There's no persistent tmux session (it uses `claude -p` print mode or `codex exec`). The integration pattern is different from dispatch.sh:

- Register once at ralph.sh startup (not per iteration)
- Heartbeat in the ralph.sh loop (not inside the agent)
- No per-agent reservations (ralph runs one task at a time, serially)
- Wake Athena on completion of all tasks, not per iteration

The PRD should either address this or explicitly say "ralph.sh integration is out of scope for v1."

### 5.3 wake-gateway.sh modification (US-023)

The PRD says "add relay wake file as fallback if callGateway fails." Looking at wake-gateway.sh, it's a simple Node.js one-liner. Adding a fallback means:

```bash
node -e "..." "$TEXT" || touch ~/.relay/wake/trigger
```

This is trivial, but the PRD should note that this creates a dependency: wake-gateway.sh now depends on the relay directory structure existing. If relay isn't installed yet (parallel run phase), the fallback should be conditional.

### 5.4 OpenClaw gateway — no documented hook mechanism

The PRD's §5.2 says "Add a file watcher (or poll in heartbeat) that scans ~/.relay/commands/." But whose heartbeat? OpenClaw's? The PRD hand-waves this as "an OpenClaw integration point, not a relay concern." But it IS a relay concern because without this integration, `relay cmd` is dead code.

Be honest about the dependency: command injection requires an OpenClaw plugin/hook that doesn't exist yet. Either scope that work into the sprints or cut `relay cmd`.

---

## 6. Sprint Ordering

### Dependencies are mostly correct

- Sprint 1 (core) has no external dependencies ✅
- Sprint 2 (reservations + wake) depends on Sprint 1 ✅
- Sprint 3 (commands + integration) depends on Sprint 2 ✅
- Sprint 4 (daemon) is independent of Sprint 3 ✅

### Reordering opportunities

**Move US-022 (dispatch.sh integration) to Sprint 2.** The integration doesn't require commands (Sprint 3). Once you have send, read, register, heartbeat, reserve, and wake, you can integrate with dispatch.sh. This gets the system into production sooner and gives real-world feedback before building commands.

**Move US-024 (--wake compound flag) to Sprint 1.** It's a trivial flag on `relay send` that calls `relay wake` internally. Agents will want this from day one. Having to run two commands (`relay send` then `relay wake`) is friction that will lead to agents skipping the wake.

**Parallelize US-015 (wake) and US-011-014 (reservations).** Wake has no dependency on reservations. If two developers are working on this, one takes wake, the other takes reservations.

### Sprint 4 should be cut, not deferred

As argued in §3.1, the daemon solves a problem that doesn't exist at current scale. Marking it "optional" signals it should be built. Mark it "not planned" and revisit if polling proves insufficient.

---

## 7. User Story Quality

### Good

- US-006 (send) is well-specified: mechanism (flock), sidecar lock file, ULID generation, broadcast behavior. Implementation-ready.
- US-010 (unit tests) has concrete targets: "10+ concurrent goroutines," "80%+ coverage." Good.
- US-018 (integration tests) has a concrete scenario. Good.
- US-032 (stress test) has specific numbers: "20 goroutines × 1000 messages, <1s." Excellent acceptance criteria.

### Needs work

- **US-012 (glob overlap)** — "a reservation A conflicts with B if any concrete path could match both A's and B's patterns" is a mathematical statement, not an implementation spec. What's the actual algorithm? Enumerate test cases in the user story, not just in prose. Acceptance criteria should list specific pattern pairs and expected outcomes.

- **US-020 (command consumption)** — "Document the contract" and "Provide a Go helper function" are two different deliverables. The Go helper is useless if the consumer is a bash script. This story needs a decision: who is the consumer, and what language does it run in?

- **US-022 (dispatch.sh update)** — "Replace MCP Agent Mail integration with relay commands" is vague. What exactly changes? The story should list:
  - Lines to add to the runner script
  - Changes to `build_coordination_context()`
  - Changes to the prompt template
  - Changes to `wake_athena()`
  - What to remove from `build_full_prompt()`
  
  The §5.1 section has some of this, but the user story itself doesn't reference it.

- **US-023 (wake-gateway.sh update)** — "Add relay wake file as fallback" is one line of code. This isn't a user story, it's a subtask of US-022.

- **US-025 (man page / --help)** — Combine with US-001 (scaffolding). Documentation should be written alongside the code, not as a separate sprint.

### Missing user stories

- **No story for removing MCP Agent Mail from agent prompts.** US-022 mentions "remove MCP Agent Mail references" but doesn't call out the specific files (TOOLS.md, AGENTS.md, templates/*.md, config/agents.json MCP config).

- **No story for verifying the migration.** After cutover, how do you verify relay is working? Run 2 agents, check coordination, verify messages arrive, verify wake works. This should be an explicit story.

---

## 8. Comparison with Alternatives

### The PRD's choice (filesystem CLI) is the right one, but consider simplifications

| Alternative | Verdict |
|---|---|
| **Unix domain socket server** | Adds a daemon requirement. The PRD's entire argument is "no daemon needed." A socket server is just MCP Agent Mail in Go. Reject. |
| **Named pipes (FIFOs)** | Tempting for push semantics, but FIFOs lose messages if nobody is reading. Not suitable for async messaging. Reject. |
| **Pure file-drop protocol** | This IS what the PRD proposes, essentially. NDJSON append is a file-drop protocol with inline content. The PRD is already the simplest viable version of this. |
| **SQLite done right** | `litestream` + WAL2 + `BEGIN IMMEDIATE` would fix MCP Agent Mail's locking issues. But adds complexity for something simpler than key-value storage. The PRD correctly rejects this. |
| **Shared memory ring buffer** | Fast, but not inspectable with `cat`. Not crash-safe. The PRD's "files are debuggable" principle is correct. Reject. |

### The real question: do we even need reservations?

File reservations exist because multiple agents might edit the same file. But in practice:
- dispatch.sh assigns agents to beads, which have distinct scopes
- Agents work in the same repo but on different features
- Git handles concurrent edits via merge/rebase

The 146 reservations in MCP Agent Mail suggest agents create them dutifully but they rarely prevent actual conflicts (the analysis doesn't mention a single conflict being caught). Reservations might be pure ceremony.

**Counter-argument**: Without reservations, two agents editing the same file will create merge conflicts that waste agent time. Even if conflicts are rare, when they happen they're expensive (agent needs to understand and resolve the conflict).

**Recommendation**: Keep reservations but make them advisory-only in v1. Don't block on conflicts — warn. The `--check` flag is the right approach. If agents routinely ignore warnings without consequence, cut reservations in v2.

---

## 9. Additional Concerns

### 9.1 Go binary distribution

The PRD assumes a Go static binary at `/usr/local/bin/relay`. This means:
- Someone needs to build it (CI or local `go build`)
- Agents need it on PATH
- Updates require rebuilding and replacing the binary

This is fine, but note that "relay" is a common name. `which relay` might collide with existing tools. Consider namespacing: `agr` (agent relay), `ar`, or keep `relay` but check for collisions during install.

### 9.2 Agent identity persistence across retries

dispatch.sh retries failed agents (up to `MAX_RETRIES`). Each retry calls `relay register` again with the same name. The PRD says "if agent dir exists, update meta.json (overwrite)." Good — this handles retries. But the old inbox still has messages from before the crash. The retried agent will see stale messages from its previous life. `--unread` with cursor will skip them (cursor persists), but if the cursor file is lost or corrupted, the agent sees ghost messages.

**Recommendation**: On re-registration, optionally reset the cursor (`--reset-cursor` flag on `relay register`).

### 9.3 Testing on this specific server

The server is a Hetzner VPS with 8GB RAM and ext4 on a single disk. No SSD TRIM issues, no NFS gotchas, no distributed filesystem concerns. The PRD's filesystem assumptions are valid for this specific deployment. If the system ever moves to a shared filesystem (NFS, CIFS), `flock` semantics change and `O_CREAT|O_EXCL` may not be atomic. Document this as a hard constraint: **relay requires a local POSIX filesystem**.

---

## 10. Summary of Actionable Items

### Must fix before implementation

1. Document that inbox readers must tolerate partial trailing lines (§1.1)
2. Fix command consumption race with sidecar claim file (§1.3)
3. ~~Address Codex compatibility~~ — INVALID: Codex runs with `--yolo`, same capabilities as Claude Code (§2.1 corrected)
4. Specify how Athena reads relay messages post-wake (§2.2)
5. Kill heartbeat background loop on agent exit (§5.1)
6. Add message body size limit (§4.4)

### Should fix

7. Move dispatch.sh integration to Sprint 2 (§6)
8. Move `--wake` flag to Sprint 1 (§6)
9. Cut Sprint 4 / daemon (§3.1)
10. Simplify glob overlap to prefix matching (§3.2)
11. Drop wake layer 2 / Unix socket (§3.3)
12. Address ralph.sh integration or explicitly exclude it (§5.2)
13. Add `--reset-cursor` to `relay register` (§9.2)

### Nice to have

14. Consider tmpfs for ~/.relay/ (§4.2)
15. Check for `relay` name collision on PATH (§9.1)
16. Add migration verification user story (§7)
