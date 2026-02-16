---
name: centurion
description: Test-gated merge. Use when merging a feature branch to main after agent work passes quality checks.
---

# Centurion (`scripts/centurion.sh`)

Merges a branch to main only if tests pass.

```bash
./scripts/centurion.sh merge <branch> <repo-path>    # Test-gated merge
./scripts/centurion.sh status [repo-path]             # Branch/merge status
```

## Flow

1. Checkout branch
2. Run test gate (language-auto-detected)
3. If tests pass → merge to main
4. Wake Athena on completion

Use after `verify.sh` passes. This is the final gate before main.
