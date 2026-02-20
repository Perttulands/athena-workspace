# Prompt Templates

Reusable prompt templates for coding agent dispatch via `dispatch.sh`.

## Templates

| Template | Purpose | Key Variables |
|----------|---------|---------------|
| feature.md | Add new functionality | `{{SPEC}}`, `{{FILES}}` |
| bug-fix.md | Fix broken behavior | `{{BUG_DESCRIPTION}}`, `{{EXPECTED_BEHAVIOR}}`, `{{FILES}}` |
| refactor.md | Restructure without behavior change | `{{GOAL}}`, `{{SCOPE}}`, `{{FILES}}` |
| docs.md | Write/update documentation | `{{TOPIC}}`, `{{FILES}}` |
| script.md | Create executable script | `{{SCRIPT_PURPOSE}}`, `{{OUTPUT_PATH}}`, `{{FILES}}` |
| custom.md | General task with time budget | `{{DESCRIPTION}}`, `{{FILES}}` |
| code-review.md | Structured JSON review | `{{FILES_CHANGED}}`, `{{DIFF}}`, `{{TIMESTAMP}}` |
| refine.md | Post-merge refinement pass | `{BRANCHES}`, `{PROJECT_CONTEXT}` |

## Common Variables

- `{{BEAD_ID}}` — Bead identifier
- `{{REPO_PATH}}` — Repository path
- `{{FILES}}` — Files to read for context

## Changelog Requirement

Every template includes a mandatory changelog constraint:

> Update `CHANGELOG.md` (Keep a Changelog format) — no changelog entry, no merge

Agents must add an entry to the repo's `CHANGELOG.md` before committing. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Structure

Every template follows: **Objective → Context → Constraints → Verify → Report**

All templates (except refine/code-review) report to Athena via final plain-text completion summary in the session output.
