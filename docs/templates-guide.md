# Templates Guide

How to use and create prompt templates for coding agents.

## Available Templates

Located in `templates/`:
- **bug-fix.md**: Fix existing broken behavior
- **feature.md**: Add new functionality
- **refactor.md**: Improve code structure without changing behavior
- **docs.md**: Write or update documentation
- **script.md**: Create standalone executable script
- **code-review.md**: Structured code review and risk finding prompt
- **refine.md**: Prompt and approach refinement tasks
- **custom.md**: Freeform task with custom description

## Template Selection

### Manual Selection

Choose based on task type:
- Broken behavior → bug-fix
- New capability → feature
- Code improvement, no behavior change → refactor
- Write/update docs → docs
- Create automation script → script
- Anything else → custom

### Automatic Selection

Use `scripts/select-template.sh` to automatically select the best template based on task description and historical scores:

```bash
# Get recommendation for a task
scripts/select-template.sh "Fix the auth timeout bug"
# → Recommended template: bug-fix
# → Success rate: 83% (12 uses)

# JSON output for programmatic use
scripts/select-template.sh --json "Add user profile page"
# → {"template":"feature","path":"templates/feature.md","success_rate":0.75,"uses":8,...}
```

**How it works:**
1. Keyword matching classifies task type (fix/bug → bug-fix, add/create → feature, etc.)
2. Checks `state/template-scores.json` for historical success rates
3. Warns if selected template has low success rate (<50%)
4. Recommends alternatives when available

**Confidence levels:**
- **High**: Success rate >70% with 5+ uses
- **Medium**: Success rate >50% with 5+ uses
- **Low**: Success rate ≤50%, or <5 uses, or no historical data

This script is called by Athena before dispatch to optimize template selection based on learned performance patterns.

## Variables

Templates use `{{VARIABLE}}` syntax for substitution.

**Common variables** (all templates):
- `{{BEAD_ID}}`: Bead identifier (e.g., bd-xyz)
- `{{REPO_PATH}}`: Absolute path to repository or worktree
- `{{FILES}}`: Comma-separated list of files to focus on
- `{{DESCRIPTION}}`: Human description of the task

**Template-specific variables:**
- Bug-fix: `{{BUG_DESCRIPTION}}`, `{{EXPECTED_BEHAVIOR}}`
- Feature: `{{SPEC}}`
- Refactor: `{{GOAL}}`, `{{SCOPE}}`
- Docs: `{{TOPIC}}`
- Script: `{{SCRIPT_PURPOSE}}`, `{{OUTPUT_PATH}}`
- Code-review: `{{REVIEW_SCOPE}}`, `{{RISK_FOCUS}}`
- Refine: `{{BASE_PROMPT}}`, `{{IMPROVEMENT_GOAL}}`
- Custom: `{{DESCRIPTION}}`

## Usage

### Manual Substitution

```bash
PROMPT=$(cat templates/bug-fix.md | \
  sed "s/{{BEAD_ID}}/bd-abc/g" | \
  sed "s|{{REPO_PATH}}|/path/to/repo|g" | \
  sed "s/{{FILES}}/src\/api.py/g" | \
  sed "s/{{BUG_DESCRIPTION}}/Crashes on empty input/g" | \
  sed "s/{{EXPECTED_BEHAVIOR}}/Should return empty list/g")

./scripts/dispatch.sh bd-abc /path/to/repo claude:opus "$PROMPT" bug-fix
```

## Template Anatomy

Every template has these sections:

1. **Objective**: What the agent must accomplish
2. **Time Budget**: Target, alert, and hard-stop times (decompose if exceeded)
3. **Context Files to Read**: Which files to examine first
4. **Constraints**: Hard rules and boundaries
5. **Verify**: How to validate work (tests, lint, etc.)
6. **Report**: Notify Athena via MCP Agent Mail `send_message` tool

## Writing Templates

Principles when creating templates:
- **Concise, high-signal**: No fluff or motivational text
- **Self-contained**: All context in the prompt
- **Fresh agent assumption**: No prior conversation history
- **Docs describe IS**: Never reference what was changed
- **Structure over discipline**: Clear sections, explicit constraints

Example structure:
```markdown
# Task: [Type]

## Objective
[Single sentence: what must be accomplished]

## Context to Read
- File: path/to/file.py (lines 10-50)
- Doc: reference/guide.md

## Constraints
- MUST read files before editing
- MUST run tests after changes
- MUST commit with atomic message

## Acceptance Criteria
- [ ] Tests pass
- [ ] No lint errors
- [ ] Docs updated if public API changed

## Report
Use MCP Agent Mail `send_message` tool to notify completion.
```

## Reporting Results

All templates instruct the agent to report via MCP Agent Mail `send_message` tool:
- **Subject**: `<task-type> complete: {{BEAD_ID}}`
- **Body**: What was done, files changed, test results, commit SHA
- If stopped at time budget, subject uses `CHECKPOINT` instead and includes decomposition proposal

## Template Scoring

Templates are scored by historical performance (see [flywheel.md](flywheel.md)):
- Success rate
- Average duration
- Retry rate

`scripts/score-templates.sh` computes scores from run data.
