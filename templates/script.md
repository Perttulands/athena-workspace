# Script Creation

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Create an executable script at `{{OUTPUT_PATH}}` that does the following:

## Purpose

{{SCRIPT_PURPOSE}}

## Context Files

{{FILES}}

## Time Budget

- **Target**: ~15 min | **Alert**: 25 min | **Hard stop**: 35 min (decompose into sub-tasks)

## Constraints

- Executable with correct shebang, `chmod +x`
- Include `--help` usage text
- Fail fast (`set -euo pipefail` for bash or equivalent)
- Handle errors with clear messages and non-zero exit codes
- Self-contained — minimize external dependencies
- Test manually before committing

## Verify

```bash
chmod +x {{OUTPUT_PATH}}
{{OUTPUT_PATH}} --help
{{OUTPUT_PATH}} [test args]
```

Do not commit if the script fails.

## Report

Use MCP Agent Mail `send_message` tool to notify completion:
- **subject**: `Script complete: {{BEAD_ID}}`
- **body**: script path, usage, test results, commit SHA
