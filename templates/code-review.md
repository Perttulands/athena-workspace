# Code Review

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Review the changes below. Output structured JSON with verdict, score, issues, and patterns.

## Changed Files

{{FILES_CHANGED}}

## Diff

```diff
{{DIFF}}
```

## Review Criteria

1. **Good taste** — edge cases handled by design, not conditional patches
2. **Simplicity** — short functions, max 3 indent levels, no over-engineering
3. **Correctness** — logic errors, error handling, resource management, null safety
4. **Test quality** — tests import from production modules (never redefine production code inline), cover edge cases
5. **Naming** — clear, descriptive, follows repo conventions
6. **Architecture** — follows existing patterns, no unnecessary abstractions
7. **Focus** — no unrelated changes
{{#if ARCHITECTURE_RULES}}
8. **Architecture rules** — adheres to docs/architecture-rules.md
{{/if}}

## Output Format

Output ONLY this JSON:

```json
{
  "bead": "{{BEAD_ID}}",
  "verdict": "accept|reject|revise",
  "score": 7,
  "summary": "One paragraph assessment.",
  "issues": [
    {
      "severity": "critical|major|minor",
      "file": "path/to/file",
      "line": 42,
      "description": "What's wrong",
      "fix": "How to fix it"
    }
  ],
  "patterns": [
    "Good: Description of positive pattern"
  ],
  "reviewed_at": "{{TIMESTAMP}}"
}
```

## Verdict Rules

- **accept**: No critical/major issues, score ≥ 7
- **revise**: Major issues or score 5-6, fixable with targeted changes
- **reject**: Critical issues or score < 5, needs rework

## Severity

- **critical**: Breaks functionality, security issue, data loss, tests that don't test real code
- **major**: Design flaw, missing error handling, poor architecture
- **minor**: Style, naming, minor optimization

## Score

- 9-10: Excellent, nothing to improve
- 7-8: Good, minor issues, merge-ready
- 5-6: Needs revisions
- 3-4: Significant rework
- 1-2: Fundamentally flawed
