# Documentation

**Bead**: `{{BEAD_ID}}` | **Repo**: `{{REPO_PATH}}`

## Objective

Write or update documentation for the topic below. Docs describe what IS, never what was.

## Topic

{{TOPIC}}

## Context Files

{{FILES}}

## Time Budget

- **Target**: ~10 min | **Alert**: 15 min | **Hard stop**: 20 min

## Constraints

- Read code first — docs must match reality
- Present tense only. No "previously", "now", or changelog language.
- Include runnable examples where applicable
- Do not change code — docs only
- If code is broken or unclear, report that instead of documenting it

## Verify

Run any code examples to confirm they work. Check that docs match actual function signatures.
Do not commit if examples fail.

## Report

Use MCP Agent Mail `send_message` tool to notify completion:
- **subject**: `Docs complete: {{BEAD_ID}}`
- **body**: what was documented, files changed, commit SHA
