# SWARM.md — Athena's Agent Swarm Playbook

## Vision

Athena is a **coordinator, not an executor**. She decomposes, dispatches, verifies. Coding agents do the work. Every agent starts fresh. Every task is a bead.

Correct behavior is enforced by **tooling and structured data**, not self-discipline. Scripts handle mechanics. JSON tracks state. Hooks enforce quality. Athena makes decisions — everything else is automated.

## Principles

1. **Beads are the source of truth.** Every task gets a bead. Bead status is authoritative over all other state.
2. **Fresh agents, always.** New session per task. Kill when done. Never reuse.
3. **The prompt is the context.** Self-contained instructions from templates. Agents may explore when needed — the prompt minimizes the need.
4. **Athena stays thin.** Delegate everything except decisions.
5. **Structure over discipline.** Scripts enforce process. JSON tracks state. Hooks verify quality. Don't rely on judgment for repeatable mechanics.
6. **Data drives improvement.** Every run produces a structured record. Periodic analysis surfaces what to improve. The flywheel turns on data, not intuition.
7. **Docs describe what IS.** Never reference previous states or changes.

## Bead Lifecycle

```
todo → active → done
              → blocked (needs input)
              → failed (max retries hit)
```

## The Flow

```
Perttu → Athena → Bead → dispatch.sh → Agent → hooks → Verify → Close Bead
```

### 1. Receive & decompose
Perttu describes what he wants. Athena interprets, decomposes into beads.

### 2. Create bead
```bash
br create --title "What needs to happen" --priority 1
```
Priority: 0=critical, 1=high, 2=medium, 3=low, 4=backlog.

### 3. Dispatch via script
```bash
./scripts/dispatch.sh <bead-id> <repo-path> claude "prompt from template"
```
The script handles everything:
- Creates tmux session named `agent-<bead-id>`
- Launches agent with correct flags
- Writes run record to `state/runs/<bead-id>.json`
- Schedules a single delayed completion check
- Writes result to `state/results/<bead-id>.json`

Athena calls one command. No manual tmux, no polling.

### 4. Monitor (non-blocking)
Athena is never blocked. Two independent completion signals:

1. **Agent mails Athena** via MCP Agent Mail (happy path — includes work summary)
2. **dispatch.sh background watcher** detects completion → writes results → sends `cron wake`

Either signal wakes Athena. Both together is ideal. Athena is free to talk to Perttu the entire time.

For >2 agents, delegate monitoring to a `sessions_spawn` sub-agent.

### 5. Verify (hook-driven)
Post-completion hook runs automatically:
- Lint check on changed files
- Test suite (if applicable)
- `ubs` scan
- Results written to run record

Athena reviews the verification results, not raw output.

### 6. Handle failure
- Max 2 retries per bead, fresh agent each time
- Each retry adjusts the prompt (more context, different approach)
- After 2 failures → bead status `failed`, escalate to Perttu

### 7. Close
```bash
br update <bead-id> --status done
```
Session auto-killed by dispatch script on completion.

## Parallel Work

Git worktrees for independent beads:
```bash
git worktree add ../repo-wt-1 -b bead-abc
```
One agent per worktree. Up to 6 simultaneous. Defer new agents if RAM >90%.

## Prompt Templates

Stored in `skills/coding-agents/references/prompt-templates.md`. Structured, not creative:
- Bug fix: file, bug description, expected behavior, test command
- Feature: spec, affected files, acceptance test
- Refactor: goal, scope, constraint (all tests must pass)
- Review: what to review, output file for findings

## Structured State

### Run records (`state/runs/<bead-id>.json`)
```json
{
  "bead": "bd-279",
  "agent": "claude",
  "model": "sonnet",
  "repo": "/path/to/repo",
  "prompt_hash": "abc123",
  "started_at": "2026-02-12T17:08:00Z",
  "finished_at": "2026-02-12T17:10:00Z",
  "exit_code": 0,
  "attempt": 1,
  "verification": { "lint": "pass", "tests": "pass", "ubs": "clean" },
  "athena_tool_calls": 1
}
```

### Active state (`state/active.json`)
```json
{
  "running": ["bd-279", "bd-280"],
  "pending_check": ["bd-281"]
}
```

## The Flywheel

```
Work → Structured Records → Periodic Analysis → Improve Templates/Scripts → Better Work
```

Analysis (weekly heartbeat or manual):
- First-attempt success rate by prompt template
- Avg retries by task type
- Completion time by agent type
- Context waste (Athena tool calls per dispatch)

Weak spots surface from data. Improvements target measured problems, not guesses.

## Tooling

| Tool | Role |
|------|------|
| dispatch.sh | Spawn agent, schedule check, write records |
| poll-agents.sh | Batch status check across all sessions |
| verify.sh | Post-completion quality gate |
| br | Create/track/close beads |
| bv | Visualize work graph |
| tmux / ntm | Agent session runtime |
| claude -p | Claude Code pipe mode |
| codex --full-auto | Codex auto mode |
| cass | Search past agent sessions |
| sessions_spawn | Delegate monitoring from Athena |

## When Athena Does It Herself

Only when ALL true:
- Trivial (< 3 tool calls)
- No code writing
- Immediate result (status check, file read, quick lookup)
