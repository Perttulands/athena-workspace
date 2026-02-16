# Documentation Index

This is Athena's operating manual. Start with AGENTS.md, then dig deeper here as needed.

## Core Operating System

- **[operating-principles.md](operating-principles.md)** — Core rules for safety, external actions, and group behavior
- **[memory-system.md](memory-system.md)** — How memory works: daily files, MEMORY.md, when to write
- **[communication.md](communication.md)** — Group chat etiquette, reactions, when to speak/stay silent
- **[heartbeat-guide.md](heartbeat-guide.md)** — Proactive work during heartbeats, what to check, tracking state
- **[context-discipline.md](context-discipline.md)** — How to protect your context window from waste

## Swarm Infrastructure

These docs describe the autonomous coding factory implementation:

| Document | Purpose | Key audience |
|----------|---------|-------------|
| [architecture.md](architecture.md) | System layers, dependency direction, component boundaries | All agents |
| [architecture-rules.md](architecture-rules.md) | Mechanically enforced invariants, linter rules | All agents |
| [beads-integration.md](beads-integration.md) | How each component integrates with beads | All agents |
| [dispatch-flow.md](dispatch-flow.md) | How dispatch.sh works end-to-end | Athena, debugging |
| [templates-guide.md](templates-guide.md) | How to use/create prompt templates | Athena |
| [state-schema.md](state-schema.md) | Run/result record formats, validation | Scripts, analysis |
| [flywheel.md](flywheel.md) | Analysis methodology, improvement loop | Analysis agents |
| [worktree-guide.md](worktree-guide.md) | Agent coordination via shared directory and MCP Agent Mail | Orchestrator, dispatch |
| [calibration-guide.md](calibration-guide.md) | Accept/reject learning system, judgment patterns | Orchestrator, analysis |
| [planning-guide.md](planning-guide.md) | Goal decomposition, task sequencing, dependency planning | Orchestrator, Athena |
| [orchestrator-guide.md](orchestrator-guide.md) | Overnight autonomous operation, safety guardrails, decision logging | Orchestrator, ops |

### Doc Gardening

The doc gardening process detects drift between documentation and actual code:

- Run `scripts/doc-gardener.sh` to scan for stale references, broken links, schema drift, and template drift
- Use `--json` for machine-readable output
- Use `--fix` to see remediation instructions for each issue
- Gardening should run periodically (weekly or after major changes) to keep docs accurate

## Testing

- **[e2e-tests.md](e2e-tests.md)** — E2E test suite (4 bash tests + runner in `tests/e2e/`)

## Changelogs

| Component | Changelog |
|-----------|-----------|
| Workspace (swarm infra) | [CHANGELOG.md](../CHANGELOG.md) |
| Truthsayer | `/home/perttu/truthsayer/CHANGELOG.md` |
| Ludus Magnus | `/home/perttu/ludus-magnus/CHANGELOG.md` |
| Oathkeeper | `/home/perttu/oathkeeper/CHANGELOG.md` |
| Athena Web | `/home/perttu/athena-web/CHANGELOG.md` |
| Argus | `/home/perttu/argus/CHANGELOG.md` |
| VPS Setup | `/home/perttu/vps-setup/CHANGELOG.md` |

## Philosophy & Identity

- [VISION.md](../VISION.md) — Why this system exists
- [SOUL.md](../SOUL.md) — Who you are
- [USER.md](../USER.md) — Who you're helping

## Tools & Configuration

- [TOOLS.md](../TOOLS.md) — Local tool configuration, paths, services
- Skills — check each skill's `SKILL.md` for usage
