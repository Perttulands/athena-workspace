# Feature PRDs

Canonical feature PRDs live in this directory:

- `docs/features/swarm-vision/PRD.md`
- `docs/features/centurion/PRD.md`
- `docs/features/relay-agent-comms/PRD.md`
- `docs/features/learning-loop/PRD.md`

Rules:

1. One feature directory per feature slug.
2. Exactly one canonical PRD file per feature: `PRD.md`.
3. PRD metadata header is required and validated by `scripts/prd-lint.sh`.
4. Canonical PRDs must describe product behavior and user outcomes:
   - Overview & Objectives
   - Target Personas & User Stories
   - Functional Requirements & Scope
   - Definition of Done
5. Execution sequencing (sprints, US checklists, Ralph-oriented task breakdowns) belongs in `docs/specs/ralph/`.
6. Historical drafts/reviews belong in `docs/archive/`, not here.
