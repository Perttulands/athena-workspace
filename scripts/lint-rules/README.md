# Lint Rules — Agent-Friendly Error Messages

This directory contains modular lint rules that output structured errors with actionable fix instructions.

## How It Works

Each rule is a standalone executable script that:
1. Takes a file path as argument
2. Checks for specific violations
3. Returns exit code 0 on pass, 1 on fail
4. On failure, outputs JSON with this structure:

```json
{
  "rule": "rule-name",
  "file": "/path/to/file.ext",
  "line": 42,
  "message": "What's wrong",
  "fix": "How to fix it"
}
```

The `fix` field is the key innovation — it tells agents exactly how to resolve the issue.

## Creating New Rules

1. Create a new script in this directory: `my-rule.sh`
2. Make it executable: `chmod +x my-rule.sh`
3. Follow this template:

```bash
#!/bin/bash
set -euo pipefail

FILE="$1"

# Check for your condition
if [[ condition ]]; then
    # Output structured error
    jq -n \
        --arg rule "my-rule" \
        --arg file "$FILE" \
        --argjson line 0 \
        --arg message "Description of the problem" \
        --arg fix "Specific instructions for fixing it" \
        '{rule: $rule, file: $file, line: $line, message: $message, fix: $fix}'
    exit 1
fi

# All good
exit 0
```

4. Test it:
```bash
scripts/lint-agent.sh --rule my-rule test-file.txt
```

## Existing Rules

- **no-hardcoded-paths.sh** — Detects hardcoded absolute paths like `/home/perttu`
- **shellcheck-wrapper.sh** — Runs shellcheck with agent-friendly fix instructions
- **json-valid.sh** — Validates JSON files and reports syntax errors

## Rule Selection

Rules are automatically applied based on file extension:
- `.sh` files: shellcheck-wrapper
- `.json` files: json-valid
- All files: no-hardcoded-paths (on text files only)

You can run a specific rule with `--rule <name>`.

## Integration

The `lint-agent.sh` runner:
- Discovers all executable `.sh` files in this directory
- Runs applicable rules on each file
- Aggregates results into JSON array
- Provides both `--json` and human-readable output

This modular design makes it easy to add domain-specific rules without modifying the runner.
