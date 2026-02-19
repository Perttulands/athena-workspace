# Learning Loop Roadmap

_Generated: 2026-02-19 by Opus Strategist_

---

## 1. Current State Summary

### Working Infrastructure
The Learning Loop has **functional core scripts** in `/home/chrote/athena/tools/learning-loop/`:

| Script | Status | Description |
|--------|--------|-------------|
| `feedback-collector.sh` | ✅ Working | Extracts feedback records from run JSONs |
| `score-templates.sh` | ✅ Working | Scores templates by pass/retry/timeout rates |
| `select-template.sh` | ✅ Working | Recommends template+agent for task type |
| `detect-patterns.sh` | ✅ Working | Finds recurring failure patterns |
| `refine-prompts.sh` | ✅ Working | Auto-generates variant templates from patterns |
| `retrospective.sh` | ✅ Working | Generates human-readable reports |
| `ab-tests.sh` | ✅ Working | Full A/B test lifecycle (create/pick/record/evaluate) |
| `guardrails.sh` | ✅ Working | Safety checks (variant limits, sample sizes, rollback) |
| `weekly-strategy.sh` | ✅ Working | Generates weekly strategy reports |
| `notify.sh` | ✅ Working | Sends notifications via wake-gateway |
| `backfill.sh` | ✅ Working | Processes historical run records |

### Current Metrics
- **Pass rate:** 35% (up from 19% baseline)
- **Runs processed:** 91+ scoreable runs
- **Feedback records:** 92+
- **Templates scored:** Multiple (template-scores.json exists)
- **Cron job:** **NOT INSTALLED** (scheduled in docs, not in crontab)

### State Data Location
```
tools/learning-loop/state/
├── feedback/        # Individual feedback records
├── scores/          # template-scores.json, agent-scores.json
└── reports/         # retrospective.json, selection-validation.md
```

### What's Notably Present
1. **Dispatch integration patch exists** (`dispatch-integration.patch`) — ready to apply
2. **A/B testing infrastructure complete** — create, pick, record, evaluate lifecycle
3. **Guardrails comprehensive** — variant limits, sample size checks, refinement loop breaker, auto-rollback
4. **Notification hooks** — integrated into all major events

### What's Notably Missing
1. **Cron automation not running** — `install-cron.sh` exists but hasn't been executed
2. **Dispatch not integrated** — patch exists but not applied to workspace dispatch.sh
3. **No Opus judge** — qualitative assessment not implemented
4. **Templates directory mismatch** — LL looks for `templates/` locally but they're in workspace
5. **Weekly strategy not scheduled** — script exists, no automation

---

## 2. Target State Summary

From the PRD, the target architecture is:

### Four Nested Loops

| Loop | Frequency | Automation | Status |
|------|-----------|------------|--------|
| **Per-run** | Immediate | feedback-collector called post-dispatch | ⚠️ Manual |
| **Hourly** | Every hour | score-templates + detect-patterns | ⚠️ Not scheduled |
| **Daily** | Every day | retrospective + recommendations | ⚠️ Not scheduled |
| **Weekly** | Every week | weekly-strategy + refinement proposals | ⚠️ Not scheduled |

### Opus Judge (New Capability)
- Opus reviews code produced by agent runs
- Rates: correctness, style, maintainability
- Detects: shortcuts, gaming tests, missed edge cases
- **Distinct from Truthsayer** (static rules) — this is qualitative judgment

### Template Refinement Workflow
1. Learning Loop detects underperforming template
2. Proposes refinement (generates variant)
3. **Athena reviews and approves** (human-in-loop gate)
4. Updated template enters A/B rotation
5. Winner promotes, loser archives

### Dispatch Integration
Target workflow:
```bash
RECOMMENDATION=$(./scripts/select-template.sh "$PROMPT")
TEMPLATE=$(echo $RECOMMENDATION | jq -r '.template')
# Use recommended template in dispatch
```

### Definition of Done (from PRD)
- [x] Feedback collection works
- [x] Template scoring works
- [x] Pattern detection works
- [x] Retrospective generation works
- [ ] **Cron job running** (scheduled but not active)
- [ ] **Opus judge integrated**
- [ ] **Dispatch integration** (auto-select template)
- [ ] **Template refinement workflow** (propose → review → deploy)
- [ ] **Weekly strategy reports** (generated, not scheduled)
- [ ] **Delta alerts** (notify on significant pass rate drops)

---

## 3. Gap Analysis

### Critical Gaps (Blocking Value Delivery)

| Gap | Impact | Effort |
|-----|--------|--------|
| **Cron not installed** | All automation is manual; no continuous improvement | S |
| **Dispatch not integrated** | Templates selected manually, data not flowing | M |
| **Templates path mismatch** | LL can't find workspace templates for refinement | S |

### High-Value Gaps

| Gap | Impact | Effort |
|-----|--------|--------|
| **Opus judge missing** | No qualitative feedback; mechanical scoring only | L |
| **Delta alerts not implemented** | Regressions go unnoticed | S |
| **Weekly strategy not scheduled** | Strategic insights only on-demand | S |

### Architectural Gaps

| Gap | Impact | Effort |
|-----|--------|--------|
| **No feedback hook in dispatch.sh** | Must call feedback-collector manually | M |
| **NO_AUTO_PROMOTE default unclear** | Promotion may bypass human review | S |
| **Scores paths hardcoded** | LL and workspace state directories differ | M |

### Data Quality Gaps

| Gap | Impact | Effort |
|-----|--------|--------|
| **Template names in scores are full prompts** | Classification broken; scores not tied to template files | M |
| **Task classification crude** | Keyword-based; misses nuance | M |

---

## 4. Implementation Roadmap

### Phase 1: Activate the Loop (Week 1)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-001** | Install cron jobs | Run `install-cron.sh` and verify crontab entries for hourly scoring, daily retrospective, weekly strategy | None | S | `crontab -l` shows learning-loop entries; manual run of each scheduled command succeeds |
| **LL-002** | Configure templates path | Set `TEMPLATES_DIR` env var in cron and scripts to point to `/home/chrote/athena/workspace/templates/` | LL-001 | S | `refine-prompts.sh --dry-run` finds workspace templates |
| **LL-003** | Apply dispatch integration patch | Apply `dispatch-integration.patch` to workspace dispatch.sh; add `--auto-select` flag | None | M | `dispatch.sh --auto-select` calls select-template.sh and logs recommendation |

### Phase 2: Close the Feedback Loop (Week 2)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-004** | Auto-collect feedback post-dispatch | Modify dispatch.sh to call `feedback-collector.sh` after run completion | LL-003 | M | Each completed dispatch creates a feedback record in `state/feedback/` |
| **LL-005** | Fix template name capture | Ensure `template` field in feedback records stores template file name (e.g., "feature"), not full prompt text | LL-004 | M | `template-scores.json` shows canonical template names like "feature", "bug-fix", not raw prompts |
| **LL-006** | Implement delta alerts | Add score regression detection to hourly scoring; notify via `notify.sh` when pass_rate drops >10% | LL-001 | S | Notification sent when template score drops significantly; dry-run test passes |

### Phase 3: Template Evolution (Week 3)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-007** | Enable refinement workflow | Configure `NO_AUTO_PROMOTE=true` by default; add review queue for variant promotions | LL-002 | S | Variants require explicit approval before promotion; log shows "gated" entries |
| **LL-008** | A/B test auto-creation | Trigger `ab-tests.sh create` automatically when `refine-prompts.sh --auto` generates a variant | LL-007 | M | New variant auto-creates A/B test with 10-run target |
| **LL-009** | A/B test tracking in dispatch | Call `ab-tests.sh record` after dispatch to track which variant ran | LL-003, LL-008 | M | A/B test run counts increment after each dispatch |

### Phase 4: Qualitative Assessment (Week 4-5)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-010** | Design Opus judge interface | Define input (run record, code diff, test results) and output (quality score, critique) schema | None | S | `docs/features/learning-loop/opus-judge-spec.md` exists with schema definitions |
| **LL-011** | Implement Opus judge script | Create `opus-judge.sh` that invokes Opus via OpenClaw CLI to assess code quality | LL-010 | L | Script returns JSON with quality score (0-1), style rating, critique text |
| **LL-012** | Integrate judge into feedback | Call `opus-judge.sh` on sample of runs; store quality score in feedback record | LL-011, LL-004 | M | Feedback records include `opus_quality_score` field; sampling rate configurable |

### Phase 5: Strategic Insights (Week 5-6)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-013** | Weekly strategy scheduling | Add weekly-strategy.sh to cron (Sunday 07:00); send summary to Athena | LL-001 | S | Strategy report generated weekly; notification delivered |
| **LL-014** | Agent performance recommendations | Add agent-specific recommendations to weekly strategy (e.g., "Claude excels at feature, struggles with refactor") | LL-013 | M | Weekly report includes agent recommendations based on score deltas |
| **LL-015** | Task classification improvement | Replace keyword-based classification with pattern matching on task structure | LL-005 | M | Classification accuracy tested against 50+ labeled examples; >90% accuracy |

### Phase 6: Observability & Hardening (Ongoing)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **LL-016** | Dashboard view | Create static HTML dashboard showing current scores, active A/B tests, recent retrospectives | LL-001 | M | `state/reports/dashboard.html` generated on schedule; viewable in browser |
| **LL-017** | Guardrail audit | Review and test all guardrails (variant limits, sample sizes, rollback triggers) | None | S | Each guardrail has a test case; all pass |
| **LL-018** | State backup automation | Cron job to backup `state/` to archive; 30-day retention | LL-001 | S | Backup script runs daily; restores tested |

---

## 5. Recommended First Three Tasks

### 🎯 LL-001: Install Cron Jobs
**Why first:** Nothing runs automatically until this is done. All the infrastructure exists but sits idle.

**Agent prompt:**
```
Navigate to /home/chrote/athena/tools/learning-loop and run:
1. ./scripts/install-cron.sh
2. Verify with: crontab -l | grep learning-loop
3. Test each scheduled command manually:
   - ./scripts/score-templates.sh
   - ./scripts/retrospective.sh  
   - ./scripts/weekly-strategy.sh
4. Ensure all complete without error.
5. Document any issues in state/reports/cron-install.md
```

**Complexity:** S  
**DoD:** Crontab shows learning-loop entries; all three scripts run successfully.

---

### 🎯 LL-002: Configure Templates Path
**Why second:** Refinement can't work if LL can't find templates. Quick fix with high downstream value.

**Agent prompt:**
```
Modify /home/chrote/athena/tools/learning-loop/scripts/refine-prompts.sh:
1. Change default TEMPLATES_DIR from $PROJECT_DIR/templates to /home/chrote/athena/workspace/templates
2. Also update guardrails.sh with same default
3. Run: ./scripts/refine-prompts.sh --dry-run
4. Verify output shows it found templates like "feature.md", "bug-fix.md"
5. Commit changes with message "fix: point TEMPLATES_DIR to workspace templates"
```

**Complexity:** S  
**DoD:** `refine-prompts.sh --dry-run` correctly identifies workspace templates.

---

### 🎯 LL-003: Apply Dispatch Integration Patch
**Why third:** Connects the loop. Without this, template selection is advisory-only and feedback doesn't flow automatically.

**Agent prompt:**
```
Apply the dispatch integration from Learning Loop to workspace:

1. Read /home/chrote/athena/tools/learning-loop/scripts/dispatch-integration.patch
2. Manually apply the changes to /home/chrote/athena/workspace/scripts/dispatch.sh:
   - Add --auto-select flag parsing
   - Add LEARNING_LOOP_DIR and SELECT_SCRIPT variables
   - Add auto-select logic block that calls select-template.sh
3. Test: ./scripts/dispatch.sh --help should show --auto-select option
4. Test: Run a mock dispatch with --auto-select and verify it logs "Auto-select advisory:"
5. Commit with message "feat: add --auto-select dispatch integration for learning-loop"

Note: The patch is a reference. The actual dispatch.sh may have diverged, so adapt rather than blind-apply.
```

**Complexity:** M  
**DoD:** `dispatch.sh --auto-select` exists, calls select-template.sh, logs recommendations.

---

## Dependency Graph

```
LL-001 (cron) ─┬─► LL-002 (templates) ─► LL-007 (refinement) ─► LL-008 (auto A/B)
               │                                                        │
               ├─► LL-006 (delta alerts)                                ▼
               │                                              LL-009 (A/B tracking)
               └─► LL-013 (weekly schedule) ─► LL-014 (agent recs)
                                                        
LL-003 (dispatch) ─► LL-004 (auto feedback) ─► LL-005 (template names) ─► LL-015 (classification)
                             │
                             ▼
                    LL-012 (judge integration)
                             ▲
                             │
LL-010 (judge spec) ─► LL-011 (judge script)
```

---

## Risk Notes

1. **Data corruption risk** during feedback schema changes (LL-005). Recommend backup before migration.
2. **Opus judge cost** (LL-011) could be significant at scale. Implement sampling from the start.
3. **Dispatch changes** (LL-003, LL-004) affect production workflows. Test in isolation first.
4. **Cron contention** — ensure learning-loop cron doesn't overlap with other scheduled jobs.

---

## Success Metrics

| Metric | Current | Target (30 days) | Target (90 days) |
|--------|---------|------------------|------------------|
| Pass rate | 35% | 50% | 70% |
| Automation coverage | 0% | 80% | 100% |
| Feedback capture rate | Manual | 90% auto | 100% auto |
| Template evolution cycles | 0 | 2 | 5+ |
| Opus judge coverage | 0% | 20% sampled | 50% sampled |

---

_This roadmap is a living document. Update after each phase completion._
