# AGENTS.md — Workspace Map

Use this file as a map only. Source-of-truth behavior lives in linked docs.

## North Star

- Canonical feature behavior lives in `docs/features/<feature>/PRD.md`.
- Execution sequencing lives in `docs/specs/ralph/` (not in canonical PRDs).
- Historical or deprecated docs live in `docs/archive/YYYY-MM/`.

## What Is Where

| Path | What belongs here |
|---|---|
| `SOUL.md` + `USER.md` | Identity, operating intent, and human context |
| `TOOLS.md` | Services, CLIs, and local environment details |
| `docs/INDEX.md` | Master documentation navigation |
| `docs/features/<feature>/PRD.md` | One canonical PRD per active feature |
| `docs/specs/ralph/` | Ralph-oriented execution specs and sequencing |
| `docs/standards/prd-governance.md` | Canonical PRD structure, policy, and enforcement |
| `docs/archive/YYYY-MM/` | Deprecated/superseded drafts, reviews, audits |
| `scripts/` | Automation, lint guards, and orchestration tooling |
| `memory/YYYY-MM-DD.md` | Daily memory log (file-based memory) |
| `state/` | Generated runs, reports, and runtime logs |
| `mythology.md` | Strategic concept and product mythology |

## Daily Loop

```bash
bd create --title "task" --priority 1
./scripts/dispatch.sh <bead> <repo> codex "prompt"
./scripts/verify.sh <repo> [bead]
./scripts/centurion.sh merge <branch> <repo>
bd close <bead>
```

## Ground Rules

- `bd` is the only bead CLI in this workspace.
- One canonical PRD per active feature: `docs/features/<feature>/PRD.md`.
- Canonical PRDs are product behavior docs, not execution checklists.
- Ralph execution checklists stay in `docs/specs/ralph/`.
- Prefer `trash` over `rm` for local cleanup.
- Never use forced git rewrites (`git push --force*`) as a retry pattern.
- Use force-push only for explicit recovery with snapshot + clear intent.

## Cleanup Plan Status

1. Canonical PRD governance and linting (`scripts/prd-lint.sh`) is in place.
2. Workspace cutover from hidden path to `/home/perttu/athena` is complete.
3. Hidden-path lint guard is active (`scripts/lint-no-hidden-workspace.sh`).
4. Compatibility symlink soak is temporary; remove after final old-path sweep.
