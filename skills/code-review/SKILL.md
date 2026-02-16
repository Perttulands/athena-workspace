---
name: code-review
description: Code review specialist agent that evaluates quality, correctness, and adherence to standards. Use when you need to review code changes, validate commits, or enforce quality gates.
---

# Code Review

```bash
./scripts/review-agent.sh <bead-id>
```

## Output

JSON to `state/reviews/<bead-id>.json`:
- `verdict`: accept | reject | revise
- `score`: 1-10
- `issues`: array of {severity, file, line, description, fix}
- `patterns`: what the code did well

## Verdicts

- **accept** (score ≥7, no critical/major): ready to merge
- **reject** (score <5, critical issues): requires rework
- **revise** (score 5-6, major issues): fixable with targeted changes

## Checks

1. Correctness — logic errors, edge cases, error handling, resource leaks
2. Tests — coverage, edge cases, no test-prod bleed
3. Naming — clear, descriptive, follows conventions
4. Complexity — single responsibility, max 3 nesting levels
5. Duplication — copy-paste detection
6. Architecture — follows existing patterns, respects architecture-rules.md

## Exit Codes

- 0: accept
- 1: reject
- 2: revise

Default model: sonnet. Use opus for complex architectural reviews.
