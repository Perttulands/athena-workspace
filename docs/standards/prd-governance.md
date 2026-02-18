# PRD Governance Standard

This document defines how feature PRDs are managed in this workspace.

## Non-Negotiables

1. `bd` is the only supported bead CLI in this workspace.
2. Every active feature has exactly one canonical PRD at `docs/features/<feature-slug>/PRD.md`.
3. Canonical PRDs include a metadata header with:
   - `feature_slug`
   - `primary_bead` (must match `bd-*`)
   - `status`
   - `owner`
   - `scope_paths`
   - `last_updated` (`YYYY-MM-DD`)
   - `source_of_truth: true`
4. Canonical PRDs are product requirement documents, not implementation task checklists.
5. Every canonical PRD must include these sections:
   - `Overview & Objectives`
   - `Target Personas & User Stories`
   - `Functional Requirements & Scope` (must/should/won't)
   - `Definition of Done`
6. Work does not start if PRD governance checks fail.
7. Verification fails if PRD governance checks fail.

## Canonical Location

- Active PRDs: `docs/features/<feature-slug>/PRD.md`
- Ralph execution specs: `docs/specs/ralph/<feature>-execution-spec.md`
- Historical material: `docs/archive/YYYY-MM/`

Do not keep active feature PRDs at repo root.
Do not put sprint task lists, US checklists, or bead execution breakdowns in canonical PRDs.
If a tool/skill generates Ralph-oriented implementation specs, store those under `docs/specs/ralph/` instead of `docs/features/`.

## Update Rule

Update `last_updated` in a feature PRD whenever commits change any path listed in that PRD's `scope_paths`.

## Enforcement

- `scripts/prd-lint.sh` validates canonical location, metadata completeness, and staleness vs `scope_paths`.
- `scripts/prd-lint.sh` also enforces required PRD sections and rejects implementation-checklist style canonical PRDs.
- `scripts/dispatch.sh` blocks dispatch if `scripts/prd-lint.sh` fails.
- `scripts/verify.sh` marks verification as failed if `scripts/prd-lint.sh` fails.

## Weekly Drift Control

Run weekly:

```bash
./scripts/doc-governance-weekly.sh
```

Recommended cron:

```cron
30 5 * * 1 /home/perttu/.openclaw/workspace/scripts/doc-governance-weekly.sh >> /home/perttu/.openclaw/logs/doc-governance-weekly.log 2>&1
```

If drift exists, the weekly script writes reports to `state/results/` and creates a `bd` bead.

## Done Criteria

- No active operational docs instruct `br`.
- Active features live under `docs/features/*/PRD.md`.
- Ralph execution specs live under `docs/specs/ralph/`.
- `scripts/prd-lint.sh` passes.
- `scripts/doc-gardener.sh` passes.
