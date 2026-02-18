# Architecture Rules — Mechanical Enforcement

This document defines the architectural invariants enforced by custom linters in `scripts/lint-rules/`.

## Layer Architecture

The system follows a strict layered architecture as defined below:

```
Layer 5: Flywheel        — analysis scripts, self-improvement
Layer 4: Templates       — structured prompts
Layer 3: Hooks           — verification scripts
Layer 2: State           — JSON records, schemas
Layer 1: Scripts         — dispatch, coordination
Layer 0: Tools           — external binaries (bd, tmux, claude)
```

## Invariants

### 1. Dependency Direction (enforced by `dependency-direction.sh`)

**Rule:** Lower layers cannot import/source higher layers.

**Rationale:** Prevents circular dependencies and keeps the architecture clean. State flows up, control flows down.

**Valid:**
- `scripts/dispatch.sh` can read `state/runs/*.json` (scripts → state)
- `templates/bug-fix.md` can reference `docs/dispatch-flow.md` (templates → docs)
- Flywheel scripts can read everything

**Invalid:**
- `scripts/validate-state.sh` cannot source `templates/helpers.sh` (scripts → templates)
- `templates/feature.md` cannot source `scripts/lib/common.sh` (templates → scripts)

**Fix:** Move shared logic to a lower layer (state/ or docs/) or use a callback pattern to invert the dependency.

### 2. Naming Conventions (enforced by `naming-conventions.sh`)

**Rule:** All files follow kebab-case naming conventions specific to their type.

**Patterns:**
- **Scripts:** `kebab-case.sh` (e.g., `dispatch.sh`, `validate-state.sh`)
- **Docs:** `kebab-case.md` (e.g., `architecture-rules.md`), except `INDEX.md`, `README.md`
- **Templates:** `kebab-case.md` (e.g., `bug-fix.md`)
- **State files:** `bd-XXXX.json` (bead ID format, e.g., `bd-1yk.json`)

**Rationale:** Consistency makes files predictable for agents. Kebab-case is URL-safe and CLI-friendly.

**Fix:** Rename file to match convention. The linter suggests the corrected name.

### 3. File Size Limits (enforced by `file-size-limit.sh`)

**Rule:** Files must stay below line count limits:
- **Scripts:** 300 lines maximum
- **Docs:** 150 lines maximum

**Rationale:** Large files are hard to reason about for both humans and agents. Enforces modularity.

**Fix:** Split into smaller modules. The linter identifies large functions or sections that could be extracted.

## Integration

These rules run automatically via `lint-agent.sh` during:
- Post-completion verification (`verify.sh`)
- Manual linting (`scripts/lint-agent.sh <file>`)

All violations include:
- **message:** What's wrong
- **fix:** Specific remediation instructions

This ensures agents can self-correct architectural drift without human intervention.

## Adding New Rules

See `scripts/lint-rules/README.md` for how to add domain-specific architecture rules.
