# AGENTS.md — Athena Repo Map

This file is a navigator. Canonical behavior and policy live in the linked docs.

## Start Here

1. `docs/INDEX.md` — full documentation index
2. `TOOLS.md` — local machine/services/tooling (generated, local)
3. `docs/standards/prd-governance.md` — PRD non-negotiables

## What Is Where

| Path | Purpose |
|---|---|
| `README.md` | System overview and repo role in the broader stack |
| `docs/features/<feature>/PRD.md` | Canonical product PRDs (source of truth) |
| `docs/specs/ralph/` | Execution specs and implementation sequencing |
| `docs/archive/YYYY-MM/` | Historical drafts, reviews, and audits |
| `scripts/` | Dispatch, verify, merge, governance automation |
| `templates/` | Dispatch prompt templates |
| `skills/` | Skill docs and operational playbooks |
| `config/agents.json` | Active agent command/model config (local) |
| `tests/e2e/` | End-to-end checks for core system behavior |
| `memory/YYYY-MM-DD.md` | Daily memory files (local, not committed) |
| `state/` | Runtime outputs, runs/results, reports (local runtime data) |

## Coordination Model

- Shared-directory, shared-branch execution; no worktree manager flow.
- `scripts/dispatch.sh` injects active-agent context to reduce overlap.
- Completion signaling is `wake-gateway` + dispatch watcher.
- `mcp-agent-mail` is retired and removed from live runtime.

## PRD Rules

- One canonical PRD per active feature: `docs/features/<feature>/PRD.md`.
- Canonical PRDs define behavior and UX outcomes, not execution checklists.
- Required sections: Overview/Objectives, Personas/User Stories, Functional Scope, Definition of Done.
- Ralph-style task sequencing belongs in `docs/specs/ralph/`.

## Daily Loop

```bash
bd create --title "task" --priority 1
./scripts/dispatch.sh <bead> <repo> <agent> "<prompt>"
./scripts/verify.sh <repo> [bead]
./scripts/centurion.sh merge <branch> <repo>
bd close <bead>
```

## Guardrails

- `bd` is the only supported bead CLI in this workspace.
- Do not use forced git rewrites as a retry pattern.
- Keep active docs accurate; move superseded material to `docs/archive/`.
- Prefer `trash` over destructive deletion.

## Maintenance Checks

```bash
./scripts/lint-no-hidden-workspace.sh
./scripts/prd-lint.sh
./scripts/doc-gardener.sh
./scripts/doc-governance-weekly.sh
```
