# Documentation Index

Start with `AGENTS.md`, then use this index for deeper docs.

## Core Operating System

- **[operating-principles.md](operating-principles.md)** - Core rules for safety and external actions
- **[memory-system.md](memory-system.md)** - Daily memory files and retention model
- **[communication.md](communication.md)** - Coordination etiquette and messaging behavior
- **[heartbeat-guide.md](heartbeat-guide.md)** - Proactive heartbeat workflows
- **[context-discipline.md](context-discipline.md)** - Context window hygiene

## Active Feature PRDs

- **[features/README.md](features/README.md)** - Canonical feature PRD layout
- **[features/swarm-vision/PRD.md](features/swarm-vision/PRD.md)** - Autonomous coding factory PRD
- **[features/centurion/PRD.md](features/centurion/PRD.md)** - Merge gate and branch control PRD
- **[features/relay-agent-comms/PRD.md](features/relay-agent-comms/PRD.md)** - Agent communication PRD
- **[features/learning-loop/PRD.md](features/learning-loop/PRD.md)** - Learning flywheel PRD

## Swarm Infrastructure

| Document | Purpose | Audience |
|----------|---------|----------|
| [architecture.md](architecture.md) | System layers, boundaries, dependencies | All agents |
| [architecture-rules.md](architecture-rules.md) | Enforced invariants and lint rules | All agents |
| [beads-integration.md](beads-integration.md) | How components create/use beads | All agents |
| [dispatch-flow.md](dispatch-flow.md) | `dispatch.sh` end-to-end behavior | Athena, debugging |
| [templates-guide.md](templates-guide.md) | Prompt template usage and maintenance | Athena |
| [state-schema.md](state-schema.md) | Run/result schema and validation | Scripts, analysis |
| [flywheel.md](flywheel.md) | Analysis loop and improvement method | Analysis agents |
| [worktree-guide.md](worktree-guide.md) | Shared-directory coordination model | Orchestrator, dispatch |
| [calibration-guide.md](calibration-guide.md) | Human accept/reject calibration system | Orchestrator |
| [planning-guide.md](planning-guide.md) | Goal decomposition and sequencing | Orchestrator |
| [orchestrator-guide.md](orchestrator-guide.md) | Overnight autonomous operation guardrails | Ops |

## Standards

- **[standards/prd-governance.md](standards/prd-governance.md)** - `bd` policy, canonical PRD rules, enforcement

## Execution Specs

- **[specs/README.md](specs/README.md)** - What execution specs are and how they differ from PRDs
- **[specs/ralph/README.md](specs/ralph/README.md)** - Ralph-oriented execution spec directory

## Doc Operations

- Run `scripts/doc-gardener.sh` for link/reference/schema/template drift
- Run `scripts/prd-lint.sh` for canonical PRD governance checks
- Run `scripts/doc-governance-weekly.sh` for weekly combined sweep + report/bead creation

## Testing

- **[e2e-tests.md](e2e-tests.md)** - End-to-end suite in `tests/e2e/`

## Archive

- Historical PRDs, reviews, and audits are in `docs/archive/`

## Philosophy & Identity

- [README.md](../README.md) - System overview
- [mythology.md](../mythology.md) - Mythology and visual identity source of truth
- [SOUL.md](../SOUL.md) - Core identity
- [USER.md](../USER.md) - Human context

## Tools & Configuration

- [TOOLS.md](../TOOLS.md) - Local services, CLI tools, paths
