# Dispatch Flow

End-to-end lifecycle of how `dispatch.sh` launches agents and tracks execution.

## Architecture

```
config/agents.json          ← single source of truth (models, flags, commands)
scripts/lib/config.sh       ← reads config, builds agent commands
scripts/lib/common.sh       ← shared utilities
scripts/lib/record.sh       ← run/result record building and validation
scripts/dispatch.sh          ← thin orchestrator sourcing the above
```

## Command

```bash
./scripts/dispatch.sh <bead-id> <repo-path> <agent-type> "<prompt>" [--branch <name>] [--force]
```

**Arguments:**
- `bead-id`: Unique identifier (e.g., bd-xyz)
- `repo-path`: Path to repository
- `agent-type`: `claude:opus`, `claude:sonnet`, `codex`, `codex:gpt-5.3-codex`
- `prompt`: Task instruction (can be from template)
- `--branch`: Shared branch name for multi-agent coordination
- `--force`: Bypass dirty worktree check (also `DISPATCH_FORCE=true`)

## Model Resolution

Priority order:
1. Colon syntax in agent-type arg: `claude:opus` → model=opus
2. Environment variable: `DISPATCH_CLAUDE_MODEL` or `DISPATCH_CODEX_MODEL`
3. Default from `config/agents.json`

Model aliases (e.g., "opus") are resolved to full names (e.g., "claude-opus-4-6") via config. Every run record logs the actual model used — never opaque.

## Flow Stages

### 1. Preflight
- Source lib files (common, config, record)
- Parse colon syntax for agent type and model
- Build agent command via `build_agent_cmd()` from config
- Validate prerequisites (jq, tmux, sha256sum)
- Check disk space (minimum 200MB at workspace and repo)
- Clean up stale status files from previous runs
- Run `agent-preflight.sh` if present

### 2. Create Run Record
- Generate `state/runs/<bead-id>.json`
- Record: agent, model, repo, prompt, started_at, attempt
- Calculate prompt_hash (SHA-256)
- Write atomically (tmp file + mv)

### 3. Launch Agent in tmux
- Create runner script in `state/watch/`
- Runner wraps agent command with exit code capture
- Runner includes signal traps (SIGTERM/SIGINT/SIGHUP) and double-emit guard
- Runner auto-commits uncommitted work on exit (`git add -A && git commit`)
- Runner writes status file with jq (falls back to printf if jq unavailable)
- Launch tmux session: `agent-<bead-id>` on coding socket
- Session runs independently

### 4. Background Watcher
- Runs as a background subshell, polls every 20s (configurable via `DISPATCH_WATCH_INTERVAL`)
- Handles signals (SIGTERM/SIGINT/SIGHUP) — marks run as failed on interrupt
- Three detection strategies (in priority order):
  1. Status file (`state/watch/<bead-id>.status.json`) — written by runner on exit
  2. Pane markers (`OPENCLAW_EXIT_CODE:N`) — backup signal in tmux output
  3. Shell prompt heuristic — detects returned-to-prompt state
- Timeout after 3600s (configurable via `DISPATCH_WATCH_TIMEOUT`) — kills tmux session on timeout
- Monitors disk space during execution — kills agent if <100MB free

### 5. Complete Run
- Capture output_summary from tmux pane (last 500 chars)
- Run `verify.sh` for post-completion quality checks
- Write final run and result records with verification data
- Advisory schema validation (warns, doesn't block)
- Kill tmux session, clean runtime files
- Stop Truthsayer watcher if running
- Append to daily memory file
- Wake Athena via `scripts/wake-gateway.sh` (calls OpenClaw's `callGateway` Node.js function directly — the `openclaw cron wake` CLI hangs due to WebSocket handshake issues)

## Retry Logic

- Max 2 retries per bead (configurable via `DISPATCH_MAX_RETRIES`)
- On failure with retries remaining: `will_retry=true` in result record
- Re-running dispatch.sh with same bead-id increments attempt counter
- After max retries: hard failure, wake Athena

## Multi-Agent Coordination

When `--branch` is specified, dispatch.sh enables coordination:

1. `build_coordination_context()` scans `state/runs/` for other active agents on the same repo
2. Injects Agent Mail instructions and co-agent awareness into the prompt
3. Agents register with MCP Agent Mail, reserve files, and message each other
4. Auto-commit on agent exit captures work (runner trap: `git add -A && git commit`)
5. When all agents finish: `centurion.sh merge <branch> <repo>` merges to main

Agents share one directory — no worktrees, no per-agent branches.

## Bead Lifecycle in Dispatch

1. Bead created via `br create` (before dispatch)
2. `dispatch.sh` launches agent, creates run/result records linked to bead
3. Agent works the task
4. `verify.sh` validates the result, writes to `state/results/<bead-id>-verify.json`
5. Bead closed via `br close` after verification

## Data Written

**Run record** (`state/runs/<bead-id>.json`): Created at dispatch, updated at completion.
**Result record** (`state/results/<bead-id>.json`): Created at dispatch, finalized at completion.

See [state-schema.md](state-schema.md) for full field definitions.
