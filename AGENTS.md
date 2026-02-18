# AGENTS.md — Entry Point

## Navigation

- [SOUL.md](SOUL.md) — Identity + operating principles
- [USER.md](USER.md) — About Perttu
- [TOOLS.md](TOOLS.md) — Server, services, CLI tools
- Skills: beads, verify, centurion, bug-scanner, argus, coding-agents
- [docs/INDEX.md](docs/INDEX.md) — Full documentation index
- [docs/standards/prd-governance.md](docs/standards/prd-governance.md) — Canonical PRD policy

## Swarm Quick Reference

```bash
bd create --title "task" --priority 1                              # Create bead
./scripts/dispatch.sh <bead> <repo> codex "prompt"                 # Dispatch (codex)
./scripts/dispatch.sh <bead> <repo> claude:opus "prompt"           # Dispatch (opus)
./scripts/verify.sh <repo> [bead]                                  # Quality gate
./scripts/centurion.sh merge <branch> <repo>                       # Test-gated merge
bd close <bead>                                                    # Close
```

## Rules

- All coding work through `dispatch.sh`. Read `coding-agents` skill.
- `bd` is the only bead CLI in this workspace.
- Every active feature must have one canonical PRD at `docs/features/<feature>/PRD.md`.
- Canonical PRDs define product behavior and UX outcomes, not implementation checklist steps.
- Ralph execution specs live under `docs/specs/ralph/`.
- Memory = files. Daily → `memory/YYYY-MM-DD.md`. Lessons → relevant doc.
- `trash` > `rm`. Ask before destructive commands.
- Docs describe what IS. No past tense.
- Never poll. Batch. Delegate monitoring when >2 agents active.
