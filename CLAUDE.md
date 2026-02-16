# CLAUDE.md — Quick Reference for Athena

## Read First (every session)
- [AGENTS.md](AGENTS.md) — Entry point, swarm commands, rules
- [SOUL.md](SOUL.md) — Identity, operating principles, commitment check
- [USER.md](USER.md) — About Perttu
- [TOOLS.md](TOOLS.md) — Server, services, CLI tools, key paths
- [MEMORY.md](MEMORY.md) — Long-term memory, active projects, core truths

## Before Dispatching Agents
- [skills/coding-agents/SKILL.md](skills/coding-agents/SKILL.md) — Dispatch skill (READ THIS)
- [docs/dispatch-flow.md](docs/dispatch-flow.md) — How dispatch.sh works
- [docs/templates-guide.md](docs/templates-guide.md) — Template system

## Architecture & Patterns
- [docs/architecture.md](docs/architecture.md) — System architecture
- [docs/architecture-rules.md](docs/architecture-rules.md) — Rules for the system
- [docs/context-discipline.md](docs/context-discipline.md) — Context window management
- [docs/orchestrator-guide.md](docs/orchestrator-guide.md) — Orchestrator patterns

## Work Tracking & State
- [docs/beads-integration.md](docs/beads-integration.md) — Beads system
- [docs/state-schema.md](docs/state-schema.md) — State files schema
- [docs/flywheel.md](docs/flywheel.md) — Agentic coding flywheel

## Operations
- [docs/heartbeat-guide.md](docs/heartbeat-guide.md) — Heartbeat system
- [docs/memory-system.md](docs/memory-system.md) — Memory file conventions
- [docs/communication.md](docs/communication.md) — Messaging rules

## Rules (from AGENTS.md)
1. All coding work through `dispatch.sh`
2. Memory = files. Write lessons immediately.
3. `trash` > `rm`. Ask before destructive commands.
4. Never poll. Batch. Delegate monitoring.
5. READ before acting. Always.
