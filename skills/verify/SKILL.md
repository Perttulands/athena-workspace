---
name: verify
description: Run quality gate on agent work. Use after coding agents complete to check lint, tests, truthsayer, and bug scan.
---

# Verify (`scripts/verify.sh`)

Quality gate after agent work. Runs 4 checks, outputs JSON.

```bash
./scripts/verify.sh <repo-path> [bead-id]
```

## Checks

1. **Lint** — `lint-agent.sh` on changed files (git diff HEAD)
2. **Tests** — auto-detects package.json / Cargo.toml / go.mod, runs with timeout
3. **Truthsayer** — anti-pattern scan (errors = fail)
4. **UBS** — universal bug scan

## Output

JSON to stdout. If bead ID provided, also writes `state/results/<bead>-verify.json`.

```json
{
  "repo": "/path",
  "bead": "bd-xxx",
  "checks": { "lint": "pass", "tests": "pass", "ubs": "clean", "truthsayer": "pass" },
  "overall": "pass"
}
```

Overall is "fail" if any check fails.
