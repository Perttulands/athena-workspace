# Calibration Guide

## Overview

The calibration system tracks human accept/reject decisions on completed beads to teach the system taste. Over time, patterns emerge that guide automatic template selection, agent choice, and autonomous operation.

## Core Concept

**Judgment without the human** is a hard problem. The calibration system solves it by:
1. Recording every human decision (accept/reject) with context
2. Analyzing patterns across templates, agents, models
3. Using these patterns to make informed autonomous decisions

## Workflow

### Recording Judgments

After reviewing a completed bead:

```bash
# Accept a bead
scripts/calibrate.sh record bd-xyz accept "Clean implementation, good tests"

# Reject a bead
scripts/calibrate.sh record bd-abc reject "Missing error handling"
```

The `record` command:
- Reads the run record for context (agent, model, template, duration, verification)
- Creates a calibration record in `state/calibration/<bead-id>.json`
- Validates against schema
- Uses atomic write (tmp + mv) for safety

### Viewing Statistics

```bash
# See accept/reject rates by template, agent, model
scripts/calibrate.sh stats
```

Output example:
```
=== Calibration Statistics ===
Total judgments: 12
Accepts: 10 (83.3%)
Rejects: 2

--- By Template ---
  feature: 5/6 (83.3%)
  bug-fix: 4/4 (100%)
  custom: 1/2 (50.0%)

--- By Agent ---
  claude: 10/12 (83.3%)

--- By Model ---
  sonnet: 10/12 (83.3%)
```

### Identifying Patterns

```bash
# Find statistically significant rejection patterns
scripts/calibrate.sh patterns
```

The `patterns` command flags:
- Templates with >3 judgments and reject rate >40%
- Agents with >3 judgments and reject rate >40%

Example output:
```
=== Calibration Patterns ===

⚠ Template 'custom': 3/5 rejections (60%)
   Recommendation: Revise template or avoid for this task type
```

### Exporting Data

```bash
# Export all calibration data as JSON
scripts/calibrate.sh export --json
```

Use this for:
- Integration with analysis tools
- Backup before major changes
- External data science workflows

## Data Structure

Each calibration record (`state/calibration/<bead-id>.json`):

```json
{
  "schema_version": 1,
  "bead": "bd-xyz",
  "decision": "accept",
  "reason": "Clean implementation, good tests",
  "decided_at": "2026-02-12T20:00:00Z",
  "run_context": {
    "agent": "claude",
    "model": "sonnet",
    "template_name": "feature",
    "duration_seconds": 120,
    "verification_overall": "pass"
  }
}
```

The `run_context` is auto-populated from the run record — you never enter it manually.

## Integration with Autonomous Operation

The orchestrator uses calibration data to:
1. **Skip risky categories**: If template X has >50% reject rate, skip tasks using it
2. **Auto-close with confidence**: If similar past beads have >90% accept rate, auto-close without human review
3. **Flag for review**: If calibration confidence is low (<50% accept rate), flag for morning review

## Calibration Confidence Levels

- **High confidence**: >3 judgments, >70% accept rate → safe for autonomous operation
- **Medium confidence**: >3 judgments, 50-70% accept rate → flag for review
- **Low confidence**: <3 judgments or <50% accept rate → always flag for review

## Best Practices

1. **Record every decision**: Accept AND reject — both teach the system
2. **Be consistent**: Use similar criteria across beads for fair pattern detection
3. **Explain rejections**: The `reason` field helps future debugging
4. **Review patterns weekly**: Run `patterns` to spot trends early
5. **Calibrate across diversity**: Don't just judge easy beads — include edge cases

## Schema Evolution

The `schema_version: 1` field supports future evolution. If we add fields (e.g., `severity`, `tags`), the version will increment and migration tools will handle legacy records.
