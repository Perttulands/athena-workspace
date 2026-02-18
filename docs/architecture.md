# System Architecture

## Overview

The autonomous coding factory is built in layers. Each layer removes reliance on human judgment for specific concerns. Dependencies flow downward only - higher layers depend on lower layers, never vice versa.

## Layers

```
Layer 5: Flywheel        — Periodic analysis → improve templates/scripts
Layer 4: Templates       — Structured prompts, consistent quality
Layer 3: Hooks           — Post-completion verification (lint, test, scan)
Layer 2: Structured State — JSON run records, tracking
Layer 1: Scripts         — dispatch.sh, verify.sh enforce process
Layer 0: Tools           — bd, tmux, claude, codex (installed)
```

### Layer 0: Tools
- **beads (bd)**: Task management CLI
- **tmux**: Session management for parallel agents
- **claude**: Claude Code agent
- **codex**: OpenAI Codex agent (if configured)
- **cass**: Cassius chat agent
- **git**: Version control

### Layer 1: Scripts
Executable automation that enforces process:
- `dispatch.sh`: Launch agents in tmux, write run records, wake Athena on completion via `wake-gateway.sh`
- `verify.sh`: Run linters, tests (with timeouts), security scans; prints test failures
- `wake-gateway.sh`: Wake OpenClaw gateway using `callGateway` from OpenClaw's Node.js internals
- `problem-detected.sh`: Create beads for problems, log to `state/problems.jsonl`, wake Athena
- `poll-agents.sh`: Check status of running agents
- `validate-state.sh`: Schema validation for JSON records

### Layer 2: Structured State
All state is JSON in `state/`:
- `state/runs/`: Run records (one per dispatch)
- `state/results/`: Result records (one per completion)
- `state/schemas/`: JSON Schema definitions

See [state-schema.md](state-schema.md) for details.

### Layer 3: Hooks
Automated quality checks integrated into dispatch completion:
- Lint via custom linter framework
- Test suite execution (with timeouts: 120s npm, 300s cargo/go)
- Truthsayer anti-pattern scanning (live during agent work, post-completion in verify)
- Security scanning (ubs)
- Results written to verification field in records

### Problem Accountability
Cross-cutting system for tracking and escalating problems:
- `problem-detected.sh` creates priority-1 beads for detected issues
- Argus wires into it for repeated operational problems
- Problems logged to `state/problems.jsonl` with source, timestamp, bead ID
- Athena waked on every problem detection

### Layer 4: Templates
Prompt templates in `templates/`:
- bug-fix.md, feature.md, refactor.md, docs.md, script.md
- Variable substitution ({{BEAD_ID}}, {{REPO_PATH}}, etc.)
- Encode lessons learned (read first, test after, atomic commits)

See [templates-guide.md](templates-guide.md) for usage.

### Layer 5: Flywheel
Self-improvement loop:
- `analyze-runs.sh`: Generate reports from run data
- `score-templates.sh`: Compute template success rates
- Template selection driven by historical performance
- Doc gardening detects stale references

See [flywheel.md](flywheel.md) for methodology.

## Dependency Direction

Strict one-way dependencies:
- Scripts can read state schemas and templates
- Templates cannot reference scripts
- State is write-only from scripts, read-only for analysis
- Tools are called by scripts, never vice versa

## Component Boundaries

Each layer has clear inputs/outputs:
- Scripts: CLI args in, JSON records out
- State: Append-only records, immutable once written
- Templates: Variables in, filled prompt out
- Analysis: JSON records in, recommendations out

## Beads as Universal Tracking

Beads are the single work tracking unit across the entire system. Every piece of work — agent tasks, detected problems, repeated issues, scan errors, unresolved commitments — is represented as a bead.

**Components that create beads:**
- **dispatch.sh**: Agent work tasks (requires bead ID to dispatch)
- **problem-detected.sh**: Detected problems from any source
- **Argus**: Repeated operational issues (via problem-detected.sh)
- **Truthsayer**: Scan errors (via `--create-beads` flag)
- **Oathkeeper**: Unresolved agent commitments

**Bead lifecycle:** created → worked on → verified → closed

The debt ceiling cron monitors open bead count and alerts when the threshold is exceeded. This prevents unbounded work accumulation.

See [beads-integration.md](beads-integration.md) for per-component integration details.

## Principles

1. **Structure over discipline**: Enforce via tooling, not prose rules
2. **Fresh agents always**: No context reuse between tasks
3. **Data drives improvement**: Records → analysis → better templates
4. **Mechanical enforcement**: Custom linters with fix instructions
5. **Docs describe what IS**: Never reference history or changes
