---
name: doc-gardener
description: Documentation quality auditor that systematically reviews and improves README files, SKILL.md files, inline code comments, JSDoc, and API documentation. Use when you need to enhance documentation clarity, completeness, or consistency.
---

# Doc Gardener

```bash
./skills/doc-gardener/doc-gardener.sh --workspace                 # Full audit
./skills/doc-gardener/doc-gardener.sh --path /path/to/project     # Specific project
./skills/doc-gardener/doc-gardener.sh --workspace --type readme    # Only READMEs
./skills/doc-gardener/doc-gardener.sh --workspace --type skills    # Only SKILL.md
./skills/doc-gardener/doc-gardener.sh --workspace --focus examples # Focus area
./skills/doc-gardener/doc-gardener.sh --workspace --format json    # JSON output
```

## What It Audits

- README files (purpose, quickstart, usage, architecture)
- SKILL.md files (frontmatter, invocation, I/O, integration)
- Inline code comments (complex logic, non-obvious decisions)
- JSDoc / function docs (params, returns, examples)
- API docs (endpoints, schemas, auth, errors)

## Quality Dimensions

1. **Clarity** — plain language, logical flow, formatting
2. **Completeness** — prerequisites, edge cases, troubleshooting
3. **Examples** — concrete, copy-pasteable, progressive complexity
4. **Consistency** — terminology, style, cross-references
5. **Technical accuracy** — correct, current, working code examples

## Output

Report to `state/doc-audits/<timestamp>-<target>.json`. Includes per-file scores, findings (major/minor/suggestion), and prioritized improvements.

## Exit Codes

- 0: completed
- 1: execution error
- 2: quality critically low (score <5)

Default model: sonnet. Use opus for critical user-facing docs.
