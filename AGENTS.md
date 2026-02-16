# AGENTS.md — Entry Point

## Navigation

- [SOUL.md](SOUL.md) — Identity + operating principles
- [USER.md](USER.md) — About Perttu
- [TOOLS.md](TOOLS.md) — Server, services, CLI tools
- Skills: beads, verify, centurion, bug-scanner, argus, coding-agents
- [docs/INDEX.md](docs/INDEX.md) — Full documentation index

## Swarm Quick Reference

```bash
br create --title "task" --priority 1                              # Create bead
./scripts/dispatch.sh <bead> <repo> codex "prompt"                 # Dispatch (codex)
./scripts/dispatch.sh <bead> <repo> claude:opus "prompt"           # Dispatch (opus)
./scripts/dispatch.sh <bead> <repo> claude:haiku "prompt" --branch feat-x  # Shared branch
./scripts/verify.sh <repo> [bead]                                  # Quality gate
./scripts/centurion.sh merge <branch> <repo>                       # Test-gated merge
br close <bead>                                                    # Close
```

## Rules

- All coding work through `dispatch.sh`. Read `coding-agents` skill.
- Memory = files. Daily → `memory/YYYY-MM-DD.md`. Lessons → relevant doc.
- `trash` > `rm`. Ask before destructive commands.
- Docs describe what IS. No past tense.
- Telegram: commands/code in separate messages, no mixed explanation.
- Never poll. Batch. Delegate monitoring when >2 agents active.
