# State Directory Schema

This directory contains structured records of swarm agent runs and results. All files are JSON format.

## Directory Structure

```
state/
├── SCHEMA.md              # This file
├── schemas/               # JSON Schema definitions
│   ├── run.schema.json    # Schema for run records
│   └── result.schema.json # Schema for result records
├── runs/                  # Agent run records (one per bead)
│   └── bd-*.json
└── results/               # Agent completion records (one per bead)
    └── bd-*.json
```

## Run Records (`state/runs/<bead-id>.json`)

Created when an agent is dispatched. Tracks the configuration and metadata of a task execution.

### Minimal Format (Current)

```json
{
  "bead": "bd-xyz",
  "agent": "claude",
  "model": "sonnet",
  "repo": "/path/to/repo",
  "started_at": "2026-02-12T17:08:00Z",
  "attempt": 1,
  "prompt": "Task description from dispatcher"
}
```

### Full Schema (Target — see `state/schemas/run.schema.json`)

```json
{
  "schema_version": 1,
  "bead": "bd-xyz",
  "agent": "claude",
  "model": "sonnet",
  "repo": "/path/to/repo",
  "prompt": "Task description",
  "prompt_hash": "abc123...",
  "started_at": "2026-02-12T17:08:00Z",
  "finished_at": "2026-02-12T17:10:00Z",
  "duration_seconds": 120,
  "status": "done",
  "attempt": 1,
  "max_retries": 2,
  "session_name": "agent-bd-xyz",
  "result_file": "state/results/bd-xyz.json",
  "exit_code": 0
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `bead` | string | Yes | Unique bead identifier (format: `bd-<id>`) |
| `agent` | string | Yes | Agent type: `"claude"` or `"codex"` |
| `model` | string | Yes | Model name (e.g., `"sonnet"`, `"gpt-5.3-codex"`) |
| `repo` | string | Yes | Absolute path to repository where work is performed |
| `started_at` | string | Yes | ISO 8601 timestamp when agent was dispatched |
| `attempt` | integer | Yes | Attempt number (1-based, increments on retries) |
| `prompt` | string | Yes | The task instruction given to the agent (truncated to 200 chars) |
| `prompt_full` | string | Yes | Full task instruction (not truncated) |
| `prompt_hash` | string | No | SHA-256 hash of prompt (for template tracking) |
| `finished_at` | string | No | ISO 8601 timestamp when agent completed |
| `duration_seconds` | integer | No | Duration in seconds |
| `status` | string | No | Outcome: `"running"`, `"done"`, `"failed"`, `"timeout"` |
| `max_retries` | integer | No | Maximum retry limit |
| `session_name` | string | No | Tmux session name |
| `result_file` | string | No | Path to corresponding result record |
| `exit_code` | integer | No | Process exit code (null if N/A) |
| `output_summary` | string | No | Last 500 chars of tmux pane output on completion |
| `failure_reason` | string | No | Structured reason when status is "failed" or "timeout" |
| `template_name` | string | No | Which prompt template was used (e.g., "bug-fix", "feature") |

### Notes

- Current implementation uses minimal format
- Full schema is the target format (see `state/schemas/run.schema.json`)
- Run records are immutable once created
- One run record per dispatch (including retries)
- Some legacy records may have placeholder timestamps like `'$START'`

## Result Records (`state/results/<bead-id>.json`)

Created when an agent completes (successfully or not). Tracks the outcome of a task execution.

### Minimal Format

```json
{
  "bead": "bd-xyz",
  "status": "done",
  "finished_at": "2026-02-12T17:10:00Z",
  "attempt": 1
}
```

### Full Schema (see `state/schemas/result.schema.json`)

```json
{
  "schema_version": 1,
  "bead": "bd-xyz",
  "agent": "codex",
  "status": "done",
  "reason": "Completed task description",
  "started_at": "2026-02-12T17:08:00Z",
  "finished_at": "2026-02-12T17:10:00Z",
  "duration_seconds": 120,
  "attempt": 1,
  "max_retries": 2,
  "will_retry": false,
  "exit_code": 0,
  "session_name": "agent-bd-xyz"
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `bead` | string | Yes | Unique bead identifier (must match run record) |
| `status` | string | Yes | Outcome: `"done"`, `"failed"`, `"timeout"`, or `"running"` |
| `finished_at` | string | Yes | ISO 8601 timestamp when agent completed |
| `attempt` | integer | Yes | Attempt number (must match run record) |
| `schema_version` | integer | No | Schema version (1 for full format) |
| `agent` | string | No | Agent type (required if schema_version=1) |
| `reason` | string | No | Human-readable completion description |
| `started_at` | string | No | ISO 8601 timestamp |
| `duration_seconds` | integer | No | Duration in seconds |
| `max_retries` | integer | No | Maximum retry limit |
| `will_retry` | boolean | No | Whether task will be retried |
| `exit_code` | integer | No | Process exit code (null if N/A) |
| `session_name` | string | No | Tmux session name |
| `output_summary` | string | No | Last 500 chars of tmux pane output on completion |

### Status Values

- `"done"` — Task completed successfully
- `"failed"` — Task failed and will not retry (max retries exceeded)
- `"timeout"` — Task exceeded time limit
- `"running"` — Task is still in progress (transitional state)

### Notes

- Result records are written by `dispatch.sh` when an agent completes
- Two formats coexist: minimal (common) and full (schema v1)
- The `reason` field in full format contains the agent's summary of work completed
- The `will_retry` field indicates if dispatcher will spawn a new attempt

## Data Flow

1. **Dispatch**: `dispatch.sh` creates a run record in `state/runs/`
2. **Execution**: Agent works in tmux session
3. **Completion**: `dispatch.sh` detects completion and writes result record to `state/results/`
4. **Analysis**: `analyze-runs.sh` merges run+result records by `bead` ID

## Relationship

Run and result records are linked by the `bead` field:

- Each bead has **exactly one** run record per attempt
- Each bead has **at most one** result record (written when agent completes)
- Multiple attempts create multiple run records with same `bead` but different `attempt` numbers

## Schema Validation

JSON Schema definitions are in `state/schemas/`:

- `run.schema.json` — Target schema for run records (full format)
- `result.schema.json` — Target schema for result records (full format)

Use `scripts/validate-state.sh` to validate records against schemas:

```bash
# Validate all run records
./scripts/validate-state.sh --runs

# Validate all result records
./scripts/validate-state.sh --results

# Validate both
./scripts/validate-state.sh --all

# Validate a specific file
./scripts/validate-state.sh --runs state/runs/bd-abc.json

# Migrate legacy records (add missing nullable fields)
./scripts/validate-state.sh --fix --runs
```

The validator uses `ajv-cli` for JSON Schema validation. Invalid records will produce clear error messages with field names. Exit code 0 = all pass, 1 = any fail.

Current records may not validate against these schemas — they represent the target format. The analysis script (`analyze-runs.sh`) handles both minimal and full formats.

## Analysis

Use `scripts/analyze-runs.sh` to generate reports:

```bash
# Human-readable report
./scripts/analyze-runs.sh

# JSON output
./scripts/analyze-runs.sh --json

# Filter by date
./scripts/analyze-runs.sh --since 2026-02-11
```

The script merges run and result records by `bead` ID and calculates:
- Total runs, success/fail counts, success rate
- Average duration per agent type (claude vs codex)
- Retry rate (tasks needing >1 attempt)
- Most common failure reasons
- Recommendations based on metric thresholds

See SWARM.md section "The Flywheel" for analysis methodology.
