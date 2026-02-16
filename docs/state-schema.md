# State Schema

Format and validation for run and result records in `state/`.

## Directory Structure

```
state/
├── schemas/
│   ├── run.schema.json     # JSON Schema for run records
│   └── result.schema.json  # JSON Schema for result records
├── runs/
│   └── <bead-id>.json      # One run record per dispatch
└── results/
    └── <bead-id>.json      # One result record per completion
```

## Run Records

Created at dispatch. Tracks configuration and metadata of task execution.

**File**: `state/runs/<bead-id>.json`

**Key fields**:
- `bead`: Unique identifier (bd-xyz)
- `agent`: Agent type (claude, codex)
- `model`: Model name (sonnet, gpt-5.3-codex)
- `repo`: Absolute path to repository
- `prompt`: Task instruction (truncated to 200 chars)
- `prompt_full`: Full task instruction
- `prompt_hash`: SHA-256 hash of prompt
- `started_at`: ISO 8601 timestamp
- `finished_at`: ISO 8601 timestamp (null if running)
- `duration_seconds`: Duration in seconds
- `status`: running, done, failed, timeout
- `attempt`: Attempt number (1-based)
- `max_retries`: Maximum retry limit
- `exit_code`: Process exit code
- `output_summary`: Last 500 chars of tmux pane output
- `failure_reason`: Structured reason when failed/timeout
- `template_name`: Which template was used (bug-fix, feature, etc.)

**Schema**: `state/schemas/run.schema.json`

## Result Records

Created at completion. Tracks outcome of task execution.

**File**: `state/results/<bead-id>.json`

**Key fields**:
- `bead`: Unique identifier (must match run record)
- `status`: done, failed, timeout, running
- `agent`: Agent type
- `started_at`: ISO 8601 timestamp
- `finished_at`: ISO 8601 timestamp
- `duration_seconds`: Duration in seconds
- `attempt`: Attempt number (must match run record)
- `max_retries`: Maximum retry limit
- `will_retry`: Whether task will be retried
- `exit_code`: Process exit code
- `output_summary`: Last 500 chars of tmux pane output
- `reason`: Human-readable completion description

**Schema**: `state/schemas/result.schema.json`

## Status Values

- `running`: Task in progress
- `done`: Completed successfully
- `failed`: Failed, max retries exceeded
- `timeout`: Exceeded time limit

## Relationship

Run and result records linked by `bead` field:
- Each bead has **exactly one** run record per attempt
- Each bead has **at most one** result record (written at completion)
- Multiple attempts create multiple run records with same bead ID

## Validation

Use `scripts/validate-state.sh` to validate against JSON schemas:

```bash
# Validate all run records
./scripts/validate-state.sh --runs

# Validate all result records
./scripts/validate-state.sh --results

# Validate specific file
./scripts/validate-state.sh --runs state/runs/bd-abc.json

# Migrate legacy records (add missing nullable fields)
./scripts/validate-state.sh --fix --runs
```

Exit code 0 = all pass, 1 = any fail.

## Data Flow

1. **Dispatch**: Creates run record in `state/runs/`
2. **Execution**: Agent works in tmux session
3. **Completion**: Writes result record to `state/results/`
4. **Analysis**: Merges run+result by bead ID

## Analysis

Use `scripts/analyze-runs.sh` to generate reports:

```bash
./scripts/analyze-runs.sh          # Human-readable
./scripts/analyze-runs.sh --json   # Machine-readable
./scripts/analyze-runs.sh --since 2026-02-11
```

Calculates:
- Success/fail counts and rates
- Average duration per agent type
- Retry rate
- Common failure reasons
- Recommendations

See [flywheel.md](flywheel.md) for analysis methodology.
