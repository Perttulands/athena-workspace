---
feature_slug: learning-loop
primary_bead: bd-tbd
status: draft
owner: athena
scope_paths:
  - scripts/analyze-runs.sh
  - scripts/score-templates.sh
  - templates/
  - docs/flywheel.md
last_updated: 2026-02-18
source_of_truth: false
---
# Execution Spec: Agent Learning Loop

**Status**: Draft  
**Author**: Athena (PRD Architect)  
**Date**: 2026-02-16  
**Stakeholder**: Perttu  

---

## 1. Problem Statement

The agentic coding swarm executes 100+ runs but **learns nothing between them**. Every dispatch starts from the same baseline prompts. Failures repeat. Template selection is manual guesswork. The system has all the raw material for a learning flywheel — structured run records, verification results, failure reasons, prompt templates — but no closed loop connecting outcomes back to inputs.

**Current state** (from 102 runs):
- 78 done, 10 failed, 2 timeout, 12 stuck running
- 95 of 102 runs use `custom` template — structured templates are underused
- 7 of 10 failures are `tmux-launch-failed` — infrastructure noise, not prompt quality
- Verification: only 14/74 pass tests, 37/74 fail tests — **agents complete but produce broken code 50% of the time**
- Zero automated feedback from verification results to prompt improvement
- `prompt-optimizer` skill exists but is never invoked automatically

The gap: **outcomes don't feed back**. The system has eyes (verify.sh) and a brain (prompt-optimizer) but no nervous system connecting them.

## 2. Vision

A closed-loop system where every agent run — success or failure — automatically improves future runs. The flywheel:

```
Dispatch → Execute → Verify → Record → Analyze → Score → Select → Refine → Dispatch
    ↑                                                                          |
    └──────────────────────────────────────────────────────────────────────────┘
```

**Measurable goal**: Within 50 runs of activation, the system achieves ≥80% verification-pass rate on dispatched tasks (up from current ~19%).

## 3. Architecture

### 3.1 The Four Loops

The system operates four nested feedback loops, each running at a different cadence:

#### Loop 1: Run Feedback (per-run, automatic)
Every completed run's verification results are written to a structured feedback record that enriches the run data with actionable signals.

```
complete_run() → verify.sh → write feedback record → tag failure pattern
```

**Already exists**: `dispatch.sh` calls `verify.sh` and writes `verification` to run records.  
**Gap**: No pattern tagging. No downstream consumer. Verification failures are recorded but never acted on.

#### Loop 2: Template Scoring (hourly or on-demand, automatic)
Aggregate run outcomes into per-template, per-agent, per-task-type performance scores.

```
state/runs/*.json → score-templates → state/scores/template-scores.json
```

**Partially exists**: `analyze-runs.sh` computes `by_template` stats. `prompt-optimizer` has `group-runs.jq`.  
**Gap**: No persistent score file. No scheduled execution. No consumption by dispatch.

#### Loop 3: Prompt Refinement (daily or threshold-triggered, semi-automatic)
When a template's score drops below threshold or a failure pattern recurs N times, generate a refined template variant.

```
template-scores.json + failure patterns → prompt-optimizer → templates/<name>-v2.md
```

**Partially exists**: `prompt-optimizer` can generate A/B variants with `--ab-test`.  
**Gap**: Never triggered automatically. No threshold logic. No variant lifecycle management.

#### Loop 4: Strategy Evolution (weekly, human-in-the-loop)
Aggregate cross-template learnings into system-level strategy changes: default agent selection, task decomposition rules, prompt engineering patterns.

```
Weekly analysis → strategy report → human review → AGENTS.md / config updates
```

**Does not exist**.

### 3.2 Data Flow

```
                    ┌─────────────┐
                    │  dispatch.sh │
                    └──────┬──────┘
                           │ dispatches agent
                           ▼
                    ┌─────────────┐
                    │  Agent Run   │
                    └──────┬──────┘
                           │ completes
                           ▼
                    ┌─────────────┐
                    │  verify.sh   │──→ verification JSON
                    └──────┬──────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  state/runs/<bead>.json │  ← enriched run record
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │  feedback-collector.sh  │  ← NEW: extracts signals
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │ state/feedback/<bead>.json │  ← NEW: structured feedback
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │   score-templates.sh    │  ← NEW: aggregates scores
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │ state/scores/           │
              │  template-scores.json   │  ← NEW: persistent scores
              │  agent-scores.json      │
              │  pattern-registry.json  │
              └────────────┬───────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                  ▼
  ┌──────────────┐ ┌──────────────┐  ┌──────────────┐
  │ select-       │ │ refine-      │  │ weekly-      │
  │ template.sh   │ │ prompts.sh   │  │ strategy.sh  │
  │ (per dispatch)│ │ (on trigger) │  │ (scheduled)  │
  └──────────────┘ └──────────────┘  └──────────────┘
         │                 │                  │
         ▼                 ▼                  ▼
  dispatch.sh picks   templates/         docs/strategy-
  best template       updated variants   report.md
```

## 4. Components

### 4.1 Feedback Collector (`scripts/feedback-collector.sh`)

**Trigger**: Called by `complete_run()` in dispatch.sh after verification completes.  
**Input**: Run record JSON + verification JSON.  
**Output**: `state/feedback/<bead>.json`

Feedback record schema:

```json
{
  "schema_version": 1,
  "bead": "bd-xxx",
  "timestamp": "2026-02-16T12:00:00Z",
  "template": "feature",
  "agent": "claude",
  "model": "opus",
  "outcome": "partial_pass",
  "signals": {
    "exit_clean": true,
    "tests_pass": false,
    "lint_pass": true,
    "ubs_clean": true,
    "truthsayer_clean": true,
    "duration_ratio": 1.2,
    "retried": false
  },
  "failure_patterns": ["test-failure-after-completion"],
  "verification_details": { ... },
  "prompt_hash": "abc123..."
}
```

**Outcome classification** (richer than pass/fail):
| Outcome | Definition |
|---|---|
| `full_pass` | exit 0 + all verification checks pass |
| `partial_pass` | exit 0 + some verification checks fail |
| `agent_failure` | exit ≠ 0 (agent crashed, timed out) |
| `infra_failure` | tmux-launch-failed, session-exited-without-markers, disk-space |
| `timeout` | watch timeout exceeded |

**Failure pattern detection** — tag each run with zero or more patterns:
| Pattern Tag | Detection Rule |
|---|---|
| `test-failure-after-completion` | exit 0 but tests fail |
| `lint-failure-after-completion` | exit 0 but lint fail |
| `scope-creep` | duration > 2× template target |
| `incomplete-work` | exit 0 but output contains "CHECKPOINT" or "remaining work" |
| `infra-tmux` | failure_reason contains "tmux" |
| `infra-disk` | failure_reason contains "disk" |
| `repeated-failure` | same prompt_hash failed before |
| `verification-gap` | no verification data (verify.sh skipped) |

### 4.2 Template Scorer (`scripts/score-templates.sh`)

**Trigger**: Cron (hourly) or called by dispatch.sh before template selection.  
**Input**: All `state/feedback/*.json` files.  
**Output**: `state/scores/template-scores.json`

Score schema:

```json
{
  "generated_at": "2026-02-16T12:00:00Z",
  "min_sample_size": 5,
  "templates": {
    "feature": {
      "total_runs": 15,
      "full_pass_rate": 0.60,
      "partial_pass_rate": 0.20,
      "agent_failure_rate": 0.13,
      "infra_failure_rate": 0.07,
      "avg_duration_seconds": 420,
      "median_duration_seconds": 380,
      "retry_rate": 0.13,
      "trend": "improving",
      "by_agent": {
        "claude": { "full_pass_rate": 0.75, "runs": 8 },
        "codex": { "full_pass_rate": 0.43, "runs": 7 }
      },
      "top_failure_patterns": [
        { "pattern": "test-failure-after-completion", "count": 3, "rate": 0.20 }
      ],
      "score": 0.72,
      "confidence": "medium"
    }
  }
}
```

**Composite score formula**:

```
score = (full_pass_rate × 1.0) + (partial_pass_rate × 0.4) - (retry_rate × 0.2) - (timeout_rate × 0.3)
```

Clamped to [0.0, 1.0]. Weighted toward `full_pass` because partial passes still waste human review time.

**Confidence levels**:
| Level | Threshold |
|---|---|
| `low` | < 5 runs |
| `medium` | 5–19 runs |
| `high` | ≥ 20 runs |

**Trend detection**: Compare last-10-runs score against all-time score. `improving` if delta > +0.05, `declining` if < -0.05, else `stable`.

### 4.3 Template Selector (`scripts/select-template.sh`)

**Trigger**: Called by dispatch.sh (or by the human/Athena before dispatch).  
**Input**: Task description string, template-scores.json.  
**Output**: Recommended template name + confidence + reasoning.

Selection algorithm:

1. **Classify task type** from prompt keywords:
   - `fix|bug|broken|crash|error` → `bug-fix`
   - `add|create|implement|build|feature` → `feature`
   - `refactor|restructure|clean|extract` → `refactor`
   - `doc|document|readme|guide` → `docs`
   - `script|automate|tool|CLI` → `script`
   - `review|audit|check` → `code-review`
   - fallback → `custom`

2. **Lookup template score**. If score exists and confidence ≥ medium:
   - If score ≥ 0.6 → recommend this template
   - If score < 0.6 → recommend but warn: "Template `X` has low success rate (Y%). Consider prompt refinement."
   - If a variant (`X-v2`) exists and has higher score → recommend variant

3. **Agent recommendation**: From `template-scores.json[template].by_agent`, recommend the agent with the highest `full_pass_rate` for this template (min 3 runs).

4. **Output format**:
   ```json
   {
     "template": "feature",
     "variant": null,
     "agent": "claude",
     "model": "opus",
     "score": 0.72,
     "confidence": "medium",
     "reasoning": "Task classified as 'feature'. Template has 72% score (15 runs). claude:opus has 75% pass rate on this template.",
     "warnings": []
   }
   ```

**Integration with dispatch.sh**: Add optional `--auto-select` flag. When set, dispatch.sh calls `select-template.sh` and uses its recommendation unless overridden.

### 4.4 Prompt Refiner (`scripts/refine-prompts.sh`)

**Trigger**: Threshold-based (automated) or on-demand.  
**Thresholds** (any triggers refinement):
- Template `full_pass_rate` drops below 0.50 (with ≥ 10 runs)
- A single failure pattern has ≥ 5 occurrences for a template
- Template trend is `declining` for 2 consecutive scoring cycles

**Input**: Template file + failure patterns + run history for that template.  
**Output**: New template variant `templates/<name>-vN.md` + changelog entry.

**Refinement strategies by failure pattern**:

| Failure Pattern | Refinement Action |
|---|---|
| `test-failure-after-completion` | Add to Verify section: "Run tests BEFORE committing. If tests fail, fix them. Do not report complete with failing tests." Add explicit test command. |
| `lint-failure-after-completion` | Add Lint section with specific linter commands from the repo. |
| `scope-creep` | Tighten time budget. Add: "If task takes >N min, STOP and decompose." Reduce target time by 20%. |
| `incomplete-work` | Add explicit acceptance criteria checklist. Add: "Verify each criterion before reporting done." |
| `repeated-failure` | Analyze common diff between successful and failed prompts for same template. Add missing context patterns. |

**Variant lifecycle**:
1. **Create**: `templates/feature-v2.md` created with refinements applied.
2. **A/B test**: Next 10 dispatches alternate between original and variant.
3. **Evaluate**: After 10 runs of each, compare scores.
4. **Promote or discard**: If variant score > original by ≥ 0.1, promote variant to `templates/feature.md` (archive original to `templates/.archive/feature-v1.md`). Otherwise discard variant.
5. **Log**: All promotions/discards recorded in `state/scores/refinement-log.json`.

**Variant tracking schema** (`state/scores/ab-tests.json`):
```json
{
  "active_tests": [
    {
      "template": "feature",
      "original": "feature.md",
      "variant": "feature-v2.md",
      "created_at": "2026-02-16T12:00:00Z",
      "original_runs": 5,
      "variant_runs": 3,
      "target_runs": 10,
      "original_score": 0.60,
      "variant_score": 0.78,
      "status": "active"
    }
  ]
}
```

### 4.5 Pattern Registry (`state/scores/pattern-registry.json`)

Central registry of all observed failure patterns with frequency, affected templates, and known mitigations.

```json
{
  "patterns": {
    "test-failure-after-completion": {
      "first_seen": "2026-02-12T10:00:00Z",
      "last_seen": "2026-02-16T08:00:00Z",
      "total_occurrences": 37,
      "by_template": { "custom": 33, "feature": 2, "script": 2 },
      "by_agent": { "claude": 20, "codex": 17 },
      "known_mitigation": "Explicit test-before-commit instruction in Verify section",
      "mitigation_effective": true
    }
  }
}
```

### 4.6 Strategy Reporter (`scripts/weekly-strategy.sh`)

**Trigger**: Weekly cron (Sunday 00:00 UTC) or on-demand.  
**Output**: `state/reports/strategy-YYYY-WNN.json` + human-readable summary to Athena.

Contents:
- Week-over-week score trends per template
- Agent performance comparison
- Top 3 failure patterns and mitigation status
- A/B test results and pending promotions
- Recommendations for:
  - Template changes
  - Default agent/model adjustments
  - Task decomposition rule updates
  - Infrastructure fixes (if infra failures > 10%)

## 5. Integration Points

### 5.1 dispatch.sh Changes

Minimal changes to existing dispatch.sh:

```bash
# In complete_run(), after write_result_record:
if [[ -x "$WORKSPACE_ROOT/scripts/feedback-collector.sh" ]]; then
    "$WORKSPACE_ROOT/scripts/feedback-collector.sh" "$RUN_RECORD" &  # non-blocking
fi

# Before agent launch (optional --auto-select mode):
if [[ "$AUTO_SELECT" == "true" && -x "$WORKSPACE_ROOT/scripts/select-template.sh" ]]; then
    SELECTION="$("$WORKSPACE_ROOT/scripts/select-template.sh" "$PROMPT")"
    TEMPLATE_NAME="$(echo "$SELECTION" | jq -r '.template')"
    echo "Auto-selected template: $TEMPLATE_NAME (score: $(echo "$SELECTION" | jq -r '.score'))"
fi
```

### 5.2 Cron Schedule

```cron
# Template scoring — every hour
0 * * * * $HOME/.openclaw/workspace/scripts/score-templates.sh

# Prompt refinement check — daily at 03:00 UTC
0 3 * * * $HOME/.openclaw/workspace/scripts/refine-prompts.sh --auto

# Strategy report — weekly Sunday 00:00 UTC
0 0 * * 0 $HOME/.openclaw/workspace/scripts/weekly-strategy.sh
```

### 5.3 Wake-Gateway Notifications

When prompt refinement creates a new variant or promotes one, `wake-gateway.sh` notifies Athena:

```
"Prompt refinement: feature-v2.md created. Trigger: test-failure-after-completion 
(5 occurrences). Changes: added explicit test verification step. A/B test active — 
next 10 feature dispatches will alternate."
```

### 5.4 Existing Tool Integration

| Existing Tool | Integration |
|---|---|
| `analyze-runs.sh` | Feeds into `score-templates.sh`. Retained for human-readable reports. |
| `prompt-optimizer` skill | `refine-prompts.sh` wraps and extends it. `analyze-patterns.sh` reused for pattern detection. |
| `verify.sh` | No changes. Already produces the verification JSON consumed by feedback-collector. |
| `truthsayer` | Truthsayer findings already recorded in run records. Feedback-collector extracts them. |
| `bd` (beads) | No changes. Bead IDs remain the primary key. |

## 6. State Schema Additions

### 6.1 New Directories

```
state/
  feedback/          # Per-run feedback records (one per bead)
  scores/            # Aggregated scores and registries
    template-scores.json
    agent-scores.json
    pattern-registry.json
    ab-tests.json
    refinement-log.json
  reports/           # Weekly strategy reports
    strategy-2026-W07.json
```

### 6.2 Templates Directory Changes

```
templates/
  .archive/          # Archived template versions after promotion
    feature-v1.md
  .ab-tests/         # A/B test metadata (already exists from prompt-optimizer)
    feature-comparison.json
  feature.md         # Current best version
  feature-v2.md      # Active A/B test variant (temporary)
```

## 7. Metrics & Success Criteria

### 7.1 Primary Metrics

| Metric | Current Baseline | 30-Run Target | 100-Run Target |
|---|---|---|---|
| Full verification pass rate | ~19% (14/74) | ≥ 50% | ≥ 80% |
| Template utilization (non-custom) | 7% (7/102) | ≥ 30% | ≥ 60% |
| Infra failure rate | 7% (7/102) | ≤ 5% | ≤ 2% |
| Retry rate | ~10% | ≤ 10% | ≤ 5% |
| Mean time to first pass | Unknown | Measured | Declining trend |

### 7.2 Secondary Metrics

- **Pattern mitigation rate**: % of known failure patterns with effective mitigations
- **Template score trend**: Week-over-week direction per template
- **A/B test velocity**: Number of variants tested per month
- **Prompt refinement hit rate**: % of refinements that improve score

### 7.3 Dashboards

`analyze-runs.sh --json` output extended with learning loop metrics. Weekly strategy report serves as the human-readable dashboard.

## 8. Implementation Plan

### Phase 1: Foundation (Week 1)
**Goal**: Close the feedback loop. Every run produces a structured feedback record.

1. **Build `feedback-collector.sh`** — Extract signals from run records, classify outcomes, tag failure patterns.
2. **Build `score-templates.sh`** — Aggregate feedback into template scores. Write `template-scores.json`.
3. **Hook into `dispatch.sh`** — Call feedback-collector from `complete_run()`.
4. **Backfill** — Run feedback-collector on all 102 existing run records to seed the scores.

**Deliverable**: `state/scores/template-scores.json` populated from historical data. Pattern registry seeded.

### Phase 2: Selection (Week 2)
**Goal**: Dispatch picks templates and agents based on data.

1. **Build `select-template.sh`** — Task classification + score lookup + agent recommendation.
2. **Add `--auto-select` to dispatch.sh** — Optional flag, advisory output.
3. **Validate** — Run 10 dispatches with auto-select. Compare to manual selection.

**Deliverable**: `dispatch.sh --auto-select` working. Template and agent recommendations logged.

### Phase 3: Refinement (Week 3)
**Goal**: Templates improve themselves.

1. **Build `refine-prompts.sh`** — Threshold detection + strategy application + variant generation.
2. **Implement A/B test lifecycle** — Alternating dispatch, score comparison, promote/discard.
3. **Wire cron jobs** — Hourly scoring, daily refinement check.
4. **Build `weekly-strategy.sh`** — Aggregate report generation.

**Deliverable**: First automated template variant created and A/B tested.

### Phase 4: Polish (Week 4)
**Goal**: The flywheel runs unattended.

1. **Notifications** — Wake-gateway alerts for refinement events, A/B results, declining scores.
2. **Guardrails** — Max variants per template (3). Minimum sample size enforcement. Rollback on score regression.
3. **Documentation** — Update `docs/flywheel.md`, `docs/templates-guide.md`, `AGENTS.md`.
4. **Retrospective** — Analyze first month of flywheel data. Tune thresholds.

**Deliverable**: System running autonomously. Human reviews weekly strategy report only.

## 9. Guardrails & Failure Modes

### 9.1 Safety Rails

| Rail | Rule |
|---|---|
| **Minimum data** | No scoring with < 5 runs. No refinement with < 10 runs. |
| **Max variants** | At most 3 active variants per template. Oldest discarded if exceeded. |
| **Human veto** | All promotions logged. Athena notifies Perttu. `--no-auto-promote` flag available. |
| **Rollback** | If promoted template scores worse than archived original for 10 runs, auto-rollback and alert. |
| **Infra isolation** | Infra failures (`tmux-launch-failed`, `disk-space`) excluded from template scoring. They're infrastructure bugs, not prompt bugs. |
| **Prompt hash tracking** | Same prompt dispatched twice is detected. Retries don't double-count for template scoring. |

### 9.2 Known Failure Modes

| Failure Mode | Mitigation |
|---|---|
| **Overfitting to small samples** | Confidence levels. No refinement below medium confidence. Bayesian prior toward 0.5 for low-data templates. |
| **Template drift** | Archive every version. Refinement log tracks all changes with rationale. |
| **Stale scores** | Scores have `generated_at`. Consumers warn if scores > 24h old. |
| **Refinement loops** | Track refinement count per template. After 5 refinements without improvement, flag for human review. |
| **Verification quality** | If verify.sh itself has bugs, scores are garbage. Separate concern — verify.sh quality tracked independently. |

## 10. What This Does NOT Include

- **Automatic task decomposition**: The learning loop scores and selects; it doesn't plan. Task decomposition remains human/Athena responsibility.
- **Model fine-tuning**: No LLM training. All learning is in template text and routing decisions.
- **Cost optimization**: Token costs not tracked (yet). Future enhancement.
- **Cross-repo learning**: Each repo's patterns may differ. Scores are currently global. Repo-specific scoring is a future enhancement.

## 11. Dependencies

| Dependency | Status | Risk |
|---|---|---|
| `jq` | Installed | None |
| `verify.sh` | Working | Low — already integrated with dispatch |
| `prompt-optimizer` skill | Working | Low — wrapping existing functionality |
| `analyze-runs.sh` | Working | None — read-only |
| Cron | Available | None |
| `wake-gateway.sh` | Working | None — existing notification path |
| Disk space for feedback records | ~1KB/record | Negligible at 100s of runs |

## 12. Open Questions

1. **Should template selection be advisory or mandatory?** Current design: advisory with `--auto-select`. Could become default behavior.
2. **How to handle the `custom` template dominance?** 95 of 102 runs use `custom`. Options: (a) auto-classify custom prompts into structured templates, (b) create sub-variants of custom for different task types, (c) accept custom as the default and refine it.
3. **Per-repo vs global scoring?** Some templates may work better for certain repos. Start global, add repo dimension later if data supports it.
4. **LLM-assisted refinement?** Instead of rule-based template edits, could dispatch an agent to rewrite the template given failure patterns. Higher quality but higher cost. Phase 5 candidate.

---

*This PRD is a living document. Update as implementation reveals what works.*
