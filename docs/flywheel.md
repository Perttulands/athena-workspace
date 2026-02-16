# Flywheel

The self-improvement loop: data collection → analysis → recommendations → better execution.

## Overview

The flywheel turns every run into learning. As more tasks execute, the system gets better at selecting templates, agents, and parameters. No manual tuning required.

## The Loop

```
Execute Tasks → Write Records → Analyze Data → Score Templates →
Select Better Templates → Execute Better → Repeat
```

## Data Collection

Every agent run produces structured JSON records:
- **Run record**: Configuration, timing, status
- **Result record**: Outcome, verification results

See [state-schema.md](state-schema.md) for formats.

## Analysis

### analyze-runs.sh

Generates reports from `state/runs/` and `state/results/`:

```bash
./scripts/analyze-runs.sh          # Human-readable summary
./scripts/analyze-runs.sh --json   # Machine-readable
./scripts/analyze-runs.sh --since 2026-02-11  # Filter by date
```

**Metrics computed**:
- Total runs, success/fail counts
- Success rate by agent type (claude vs codex)
- Success rate by model
- Average duration by agent
- Retry rate (tasks needing >1 attempt)
- Most common failure reasons

**Output sections**:
- `by_agent`: Metrics per agent type
- `by_model`: Metrics per model
- `by_template`: Metrics per template (future)
- `recommendations`: Actionable suggestions

### score-templates.sh (Future)

Computes template-level success metrics:
- Success rate per template
- Average duration per template
- Retry rate per template
- Total uses

Writes `state/template-scores.json` for template selection.

## Template Selection

### Manual (Current)

Athena picks template based on task description.

### Automatic (Future)

`scripts/select-template.sh` classifies task and recommends template:
- Uses keyword matching (fix/bug → bug-fix, add/create → feature)
- Checks `state/template-scores.json` for historical performance
- Warns if selected template has low success rate
- Suggests alternatives

## Doc Gardening

Automated documentation maintenance:

`scripts/doc-gardener.sh` scans `docs/` for:
- **Stale references**: Mentions of files that no longer exist
- **Broken links**: References to docs that don't exist
- **Schema drift**: docs/state-schema.md vs actual schemas
- **Template drift**: docs/templates-guide.md vs actual templates

Outputs JSON report with fix instructions.

## Recommendations

Analysis produces actionable recommendations:
- "Codex has 40% success rate on refactor tasks - prefer claude"
- "Feature template averages 180s - consider time limit increase"
- "Template X has 65% failure rate - review and update"

## Improvement Cycle

1. **Baseline**: Run tasks with current templates
2. **Measure**: Analyze success rates, durations, failures
3. **Adjust**: Update templates based on patterns
4. **Validate**: Next runs show improvement
5. **Repeat**: Continuous refinement

## Guardrails

- Minimum data threshold: Need 5+ runs per template for valid scoring
- Statistical significance: Only flag patterns with >3 data points
- Advisory not mandatory: Recommendations don't block execution

## Future Enhancements

- Automatic template updates based on common failures
- Model routing based on task complexity
- Calibration system learning from accept/reject decisions
- Planning layer decomposing goals into task sequences
