# Centurion Pre-commit Hook

Use Centurion's `check` command to run quick quality gates before commits.

## Install

Create `.git/hooks/pre-commit` in your target repository:

```bash
#!/usr/bin/env bash
set -euo pipefail

CENTURION="/home/chrote/athena/workspace/scripts/centurion.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"

"$CENTURION" check --level quick --quiet "$REPO_ROOT"
```

Then make it executable:

```bash
chmod +x .git/hooks/pre-commit
```

## Notes

- `--level quick` runs fast local checks (lint-focused).
- Use `--level standard` if you also want tests and Truthsayer in pre-commit.
- For troubleshooting, remove `--quiet` or add `--verbose`.
