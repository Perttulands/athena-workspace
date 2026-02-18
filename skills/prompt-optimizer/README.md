# Prompt Optimizer

Empirical prompt template optimization based on run history analysis.

## Philosophy

Traditional prompt engineering is speculative. This tool is **evidence-based**: it analyzes actual agent behavior (retries, failures, duration outliers) to identify weak patterns and suggest concrete improvements.

## How It Works

### 1. Data Collection

Reads `state/runs/*.json` files containing:
- `template_name`: Which template was used
- `status`: completed, failed, running
- `attempt`: Retry count
- `duration_seconds`: How long it took
- `failure_reason`: Why it failed (if applicable)
- `bead`: Identifier for correlation

### 2. Pattern Detection

Identifies problematic patterns:

#### High Retry Rate
**Signal**: `attempt > 1` is common for a template
**Diagnosis**: Instructions unclear, missing context, or bad variable substitution
**Fix**: Add validation steps, fallback discovery, clearer constraints

#### High Failure Rate
**Signal**: `status == "failed"` occurs >40% of the time
**Diagnosis**: Fundamental template issues (unclear acceptance criteria, scope too large)
**Fix**: Add verification checklists, stricter quality gates

#### Duration Outliers
**Signal**: Max duration >> average duration, and >300s
**Diagnosis**: Scope creep, unbounded exploration, missing boundaries
**Fix**: Add time budgets, explicit scope boundaries, decomposition triggers

#### Recurring Failures
**Signal**: Same `failure_reason` appears multiple times
**Diagnosis**: Known failure mode without recovery path
**Fix**: Add explicit error handling section for that failure

### 3. Recommendation Generation

For each identified issue, generates:
- **Section**: Which part of template to change (Objective, Constraints, etc.)
- **Change Type**: add_constraint, clarify, add_checklist, scope_boundary, add_section
- **Suggestion**: Specific text to add or modify
- **Rationale**: Why this change addresses the pattern

### 4. A/B Testing

Creates side-by-side variants for empirical validation:
- Original template (unchanged baseline)
- Variant template (with optimization annotations)
- Comparison metadata (tracks which version is used)

Dispatch both templates in round-robin fashion, compare success rates after N runs.

## Usage Examples

### Basic Analysis

```bash
./skills/prompt-optimizer/optimize-prompts.sh
```

Output:
```
=== Prompt Optimization Report ===
Generated: 2026-02-12T20:45:00Z

Analyzed 42 total runs

Template: feature.md
  Total Runs: 12
  Success Rate: 58% (7/12)
  Retry Rate: 33%
  Avg Duration: 267s

  Issues Identified:
    - [major] High retry rate (33%) indicates unclear instructions or missing context
    - [major] Significant duration outliers (max: 523s, avg: 267s) suggest scope creep

  Recommendations:
    1. [Constraints] Add explicit pre-work validation steps
    2. [Context Files to Read] Add fallback discovery step if context files list is empty
    3. [Objective] Add explicit scope boundaries and time budget
    4. [Constraints] Add 'If task requires >30 minutes, break into sub-tasks'

---

Template: bug-fix.md
  Total Runs: 18
  Success Rate: 94% (17/18)
  Retry Rate: 5%
  Avg Duration: 145s

  No issues identified. Template performing well.

---
```

### Template-Specific Analysis

```bash
./skills/prompt-optimizer/optimize-prompts.sh --template feature
```

Focuses on a single template for detailed diagnosis.

### JSON Output for Automation

```bash
./skills/prompt-optimizer/optimize-prompts.sh --json > state/optimization-report.json
```

Machine-readable output for integration with other tools:

```json
{
  "generated_at": "2026-02-12T20:45:00Z",
  "analyzed_runs": 42,
  "templates": [
    {
      "name": "feature.md",
      "metrics": {
        "total_runs": 12,
        "success_rate": 0.58,
        "retry_rate": 0.33,
        "avg_duration_seconds": 267
      },
      "issues": [
        {
          "severity": "major",
          "category": "high_retry_rate",
          "description": "High retry rate (33%) indicates unclear instructions",
          "recommendations": [
            {
              "section": "Constraints",
              "suggestion": "Add explicit pre-work validation steps"
            }
          ]
        }
      ]
    }
  ]
}
```

### A/B Test Generation

```bash
./skills/prompt-optimizer/optimize-prompts.sh --ab-test feature
```

Output:
```
Generated A/B test variant:
  Original:    templates/feature.md
  Variant:     templates/feature-v2.md
  Comparison:  templates/.ab-tests/feature-comparison.json

Recommended changes (review and apply manually to variant):
Add explicit pre-work validation steps (e.g., 'Verify all {{VARIABLES}} are non-empty')
Add fallback discovery step if context files list is empty
Add explicit scope boundaries and time budget

Next steps:
1. Review and manually edit templates/feature-v2.md to apply optimizations
2. Use both templates in round-robin dispatch for next 10 runs
3. Re-run optimizer to compare success rates
```

## Integration Points

### With Template Scoring

If `scripts/score-templates.sh` exists, the optimizer can combine:
- **Static analysis**: Template structure, readability, completeness (from scorer)
- **Dynamic analysis**: Runtime behavior, success rates, retries (from optimizer)

Example integration:
```bash
# Score templates (static)
./scripts/score-templates.sh > state/template-scores.json

# Analyze runs (dynamic)
./skills/prompt-optimizer/optimize-prompts.sh --json > state/run-analysis.json

# Combine
jq -s '.[0].templates as $scores | .[1].templates | map(
  . as $analysis |
  ($scores | map(select(.name == $analysis.name))[0]) as $score |
  . + {static_score: $score}
)' state/template-scores.json state/run-analysis.json
```

### With Dispatch Automation

Dispatch scripts can read `.ab-tests/` metadata to implement round-robin:

```bash
TEMPLATE="feature"
COMPARISON="templates/.ab-tests/${TEMPLATE}-comparison.json"

if [[ -f "$COMPARISON" ]] && jq -e '.test_status == "active"' "$COMPARISON" &>/dev/null; then
  # A/B test active, alternate between original and variant
  RUNS_SO_FAR=$(jq '.runs_dispatched // 0' "$COMPARISON")
  if (( RUNS_SO_FAR % 2 == 0 )); then
    USE_TEMPLATE="templates/${TEMPLATE}.md"
  else
    USE_TEMPLATE="templates/${TEMPLATE}-v2.md"
  fi
  # Update run count
  jq '.runs_dispatched = (.runs_dispatched // 0) + 1' "$COMPARISON" > "$COMPARISON.tmp"
  mv "$COMPARISON.tmp" "$COMPARISON"
else
  # No A/B test, use original
  USE_TEMPLATE="templates/${TEMPLATE}.md"
fi

# Dispatch with selected template
./scripts/dispatch.sh "$BEAD_ID" "$REPO" claude "$(cat "$USE_TEMPLATE")"
```

### With Code Review

Code review results can feed back into optimization:

```bash
# Extract "patterns" (what agents did well) from reviews
jq -r '.patterns[]' state/reviews/*.json | sort | uniq -c | sort -rn > state/good-patterns.txt

# Use to validate that optimizations don't remove good patterns
```

## Limitations

### Sample Size
- Requires multiple runs per template for statistical validity
- Minimum 5 runs recommended per template for meaningful analysis
- Outliers may skew results with <10 runs

### Causation vs Correlation
- High retry rate might indicate template issues OR harder tasks being assigned to that template
- Always combine quantitative metrics with qualitative review

### Template Evolution
- As templates change, old run data becomes less relevant
- Consider versioning templates or filtering runs by date range

### Variable Substitution
- Can't detect issues in how variables are filled (e.g., always-empty `{{FILES}}`)
- Requires inspection of actual prompts sent, not just templates

## Future Enhancements

### Automatic Application
Currently generates recommendations manually applied. Could auto-generate variant with changes:
```bash
./skills/prompt-optimizer/optimize-prompts.sh --ab-test feature --auto-apply
```

### Trend Analysis
Track metrics over time to see if changes improved performance:
```bash
./skills/prompt-optimizer/optimize-prompts.sh --trend --since "2026-02-01"
```

### Cross-Template Learning
Identify patterns that work well in one template and suggest applying to others:
```bash
./skills/prompt-optimizer/optimize-prompts.sh --cross-pollinate
```

### Integration with Wake Callback
Auto-report optimization suggestions to Athena when degradation detected:
```bash
# In cron or watch loop
BEFORE=$(jq '.templates[] | select(.name == "feature.md") | .metrics.success_rate' state/last-optimization.json)
AFTER=$(./skills/prompt-optimizer/optimize-prompts.sh --json | jq '.templates[] | select(.name == "feature.md") | .metrics.success_rate')
if (( $(echo "$AFTER < $BEFORE - 0.1" | bc -l) )); then
  # Success rate dropped >10%, wake Athena
  ./scripts/wake-gateway.sh "Template degradation alert: feature.md success rate dropped from $BEFORE to $AFTER"
fi
```

## Dependencies

- `jq` - JSON parsing and manipulation
- `bc` - Floating-point arithmetic
- `bash` 4.0+ - Associative arrays, process substitution

## File Structure

```
skills/prompt-optimizer/
├── SKILL.md                  # Skill metadata and usage
├── optimize-prompts.sh       # Main entry point
├── analyze-patterns.sh       # Pattern detection logic (sourced)
└── README.md                 # This file

templates/
├── feature.md                # Original templates
├── feature-v2.md             # Generated variant (if A/B testing)
└── .ab-tests/
    └── feature-comparison.json  # A/B test metadata

state/
├── runs/
│   └── *.json                # Input: run history
└── optimization-report.json  # Output: analysis results
```

## Examples

### Weekly Optimization Workflow

```bash
#!/usr/bin/env bash
# weekly-optimization.sh

WORKSPACE="$HOME/athena"
cd "$WORKSPACE"

# Generate report
./skills/prompt-optimizer/optimize-prompts.sh --json > state/optimization-report-$(date +%Y%m%d).json

# Find worst performer
WORST=$(jq -r '.templates | sort_by(.metrics.success_rate) | .[0].name' state/optimization-report-$(date +%Y%m%d).json)

if [[ -n "$WORST" ]]; then
  echo "Worst performing template: $WORST"

  # Generate A/B test variant
  ./skills/prompt-optimizer/optimize-prompts.sh --ab-test "${WORST%.md}"

  # Notify Athena
  REPORT=$(jq -r --arg tpl "$WORST" '.templates[] | select(.name == $tpl) | "Success rate: \(.metrics.success_rate * 100 | floor)%\nRetry rate: \(.metrics.retry_rate * 100 | floor)%"' state/optimization-report-$(date +%Y%m%d).json)

  ./scripts/wake-gateway.sh "Weekly optimization: $WORST needs attention. $REPORT"
fi
```

### Compare Before/After A/B Test

```bash
#!/usr/bin/env bash
# compare-ab-test.sh <template-name>

TEMPLATE="$1"
ORIGINAL="${TEMPLATE}.md"
VARIANT="${TEMPLATE}-v2.md"

# Get runs using original
ORIGINAL_RUNS=$(jq --arg tpl "$ORIGINAL" '[.[] | select(.template_name == $tpl)]' state/runs/*.json)
ORIGINAL_SUCCESS=$(jq '[.[] | select(.status == "completed")] | length' <<<"$ORIGINAL_RUNS")
ORIGINAL_TOTAL=$(jq 'length' <<<"$ORIGINAL_RUNS")

# Get runs using variant
VARIANT_RUNS=$(jq --arg tpl "$VARIANT" '[.[] | select(.template_name == $tpl)]' state/runs/*.json)
VARIANT_SUCCESS=$(jq '[.[] | select(.status == "completed")] | length' <<<"$VARIANT_RUNS")
VARIANT_TOTAL=$(jq 'length' <<<"$VARIANT_RUNS")

echo "A/B Test Results for $TEMPLATE"
echo "================================"
echo "Original ($ORIGINAL):"
echo "  Runs: $ORIGINAL_TOTAL"
echo "  Success Rate: $(echo "scale=2; $ORIGINAL_SUCCESS / $ORIGINAL_TOTAL * 100" | bc)%"
echo ""
echo "Variant ($VARIANT):"
echo "  Runs: $VARIANT_TOTAL"
echo "  Success Rate: $(echo "scale=2; $VARIANT_SUCCESS / $VARIANT_TOTAL * 100" | bc)%"
echo ""

# Statistical significance test (simple chi-square approximation)
# (Requires larger sample sizes for validity)
if (( ORIGINAL_TOTAL >= 10 && VARIANT_TOTAL >= 10 )); then
  echo "Sample sizes sufficient for comparison"
else
  echo "Warning: Sample sizes too small for statistical significance"
fi
```

## Maintenance

### Archiving Old Runs

As runs accumulate, consider archiving old data:

```bash
# Archive runs older than 30 days
find state/runs -name "*.json" -mtime +30 -exec mv {} state/runs/archive/ \;
```

### Cleaning Up A/B Tests

Once a variant proves superior, promote it:

```bash
TEMPLATE="feature"
# Replace original with variant
mv "templates/${TEMPLATE}-v2.md" "templates/${TEMPLATE}.md"
# Archive comparison metadata
mv "templates/.ab-tests/${TEMPLATE}-comparison.json" "templates/.ab-tests/archive/"
```
