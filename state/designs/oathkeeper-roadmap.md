# Oathkeeper Implementation Roadmap

_Generated: 2026-02-19_
_Source: PRD.md + README.md + AGENTS.md analysis_

---

## 1. Current State Summary

**Oathkeeper is functional but incomplete.** The core pipeline works end-to-end for manual use, but automation and integration gaps prevent production-grade operation.

### What Works Today

| Component | Status | Notes |
|-----------|--------|-------|
| CLI Commands | ✅ Working | `scan`, `list`, `stats`, `resolve`, `doctor` |
| Transcript Parsing | ✅ Working | JSONL format (OpenClaw sessions) |
| Commitment Detection | ✅ Working | Pattern matching + LLM classification |
| SQLite Storage | ✅ Working | Commitments persisted locally |
| Beads Integration | ✅ Partial | `bd create` integration exists |
| Config File | ✅ Working | `~/.config/oathkeeper/oathkeeper.toml` |
| Cron Job | ✅ Scheduled | 06:30 daily scan |

### Known Issues

1. **Detector too aggressive** — Flags conversational text as commitments ("you could do X" misclassified as "I'll do X")
2. **Grace period not implemented** — No wait-before-flag logic
3. **Bead creation not automated** — Manual trigger required
4. **No external integration** — Runs in isolation, no Relay connectivity

---

## 2. Target State Summary

**Oathkeeper as autonomous accountability system.** Scans transcripts daily, categorizes commitments with appropriate grace periods, auto-creates beads for broken promises, alerts through Relay, and tracks promise-keeping metrics.

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Daily Flow                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Cron triggers scan (06:30)                                  │
│  2. Parse new transcripts since last run                        │
│  3. Detect commitments (min_confidence: 0.7+)                   │
│  4. Categorize → assign grace period                            │
│  5. Store in SQLite with expiry timestamp                       │
│  6. Check expired commitments for backing                       │
│  7. No backing → create bead + alert via Relay                  │
│  8. Log stats, update dashboard                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Target Commitment Categories

| Category | Example | Grace Period |
|----------|---------|--------------|
| `explicit_promise` | "I'll fix that in the next step" | 1 hour |
| `will_do` | "I'll add tests later" | 24 hours |
| `todo_mention` | "TODO: handle edge case" | 7 days |
| `bug_acknowledged` | "That's an existing bug" | 24 hours |

### Definition of Done (from PRD)

- [x] Core scanner works
- [x] CLI functional
- [x] Config file support
- [x] Cron job scheduled
- [ ] Sensitivity tuned (fewer false positives)
- [ ] Automated bead creation working
- [ ] Grace period logic implemented
- [ ] Relay integration for alerts
- [ ] Stats dashboard

---

## 3. Gap Analysis

### GAP-1: Detector Sensitivity (High Priority)

**Current:** Classifier flags too many false positives. Conversational text like "you could add error handling" gets misclassified as a commitment.

**Target:** `min_confidence: 0.7` threshold. Clear distinction between:
- Agent commits to action → Track
- Agent suggests possibility → Ignore
- User requests action → Ignore (user's responsibility, not agent's)

**Effort:** Medium — Requires prompt tuning and possibly training data adjustments.

### GAP-2: Grace Period Logic (High Priority)

**Current:** No grace period implementation. Commitments flagged immediately.

**Target:** Category-aware grace periods (1hr → 7d range). Commitments stored with `expires_at` timestamp. Only checked for backing after expiry.

**Effort:** Medium — Requires schema changes and state machine for commitment lifecycle.

### GAP-3: Automated Bead Creation (Medium Priority)

**Current:** `bd create` integration exists but requires manual trigger.

**Target:** When grace period expires and no backing found:
1. Auto-execute `bd create --title "..." --tags oathkeeper`
2. Link bead ID back to commitment record
3. Mark commitment as `bead_created`

**Effort:** Small — Wiring exists, needs automation trigger.

### GAP-4: Relay Integration (Medium Priority)

**Current:** No external communication. Oathkeeper runs silently.

**Target:** 
- Send commitment alerts via Relay → Athena → user notification
- Receive resolution confirmations back
- Support `oathkeeper:commitment_created`, `oathkeeper:commitment_broken` event types

**Effort:** Large — Requires Relay protocol understanding, event schemas, bidirectional flow.

### GAP-5: Stats Dashboard (Low Priority)

**Current:** `oathkeeper stats` exists but minimal.

**Target:**
- Promise-keeping rate over time
- Breakdown by agent, category, project
- Trend analysis (are agents getting better?)
- Export-friendly format (JSON/CSV)

**Effort:** Medium — Analytics layer on existing data.

### GAP-6: Backing Verification (Medium Priority)

**Current:** Unknown verification depth. PRD mentions checking for "bead, cron, state file."

**Target:** Explicit verification strategies:
- Bead search: `bd list --query "..."`
- Cron check: grep crontab
- State file check: configurable paths
- PR/commit search: optional git integration

**Effort:** Medium — Extensible verification framework.

---

## 4. Implementation Roadmap

### Phase 1: Core Reliability (Week 1-2)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| OK-01 | Tune detector confidence threshold | Add `min_confidence` config option (default 0.7). Filter out low-confidence detections before storage. Log rejected candidates at debug level for analysis. | None | S | `oathkeeper scan` respects `min_confidence` from config. False positives reduced by >50% on test corpus. |
| OK-02 | Improve commitment prompt | Refine LLM classification prompt to distinguish between (a) agent self-commitment, (b) suggestion to user, (c) user request. Only track (a). Add test cases for each category. | None | M | New prompt with 10+ test cases. Accuracy >90% on labeled dataset. |
| OK-03 | Add commitment categories | Extend SQLite schema: `category` column (enum: explicit_promise, will_do, todo_mention, bug_acknowledged). Classify commitments at detection time. | OK-02 | S | Schema migrated. `oathkeeper list` shows category column. |
| OK-04 | Implement grace period storage | Add `detected_at`, `grace_hours`, `expires_at` columns. Compute `expires_at = detected_at + grace_hours` based on category. | OK-03 | S | Commitments stored with expiry. `oathkeeper list` shows time remaining. |
| OK-05 | Build grace period checker | New subcommand or cron mode: `oathkeeper check-expired`. Only processes commitments where `now > expires_at` AND `status = pending`. | OK-04 | M | `oathkeeper check-expired` finds and reports overdue commitments. |

### Phase 2: Automation (Week 2-3)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| OK-06 | Implement backing verification | Create verification framework. Start with bead search: `bd list --json` and match against commitment text. Return `backed: bool, backing_type: string, backing_id: string`. | OK-05 | M | Overdue commitments checked against beads. Backed commitments auto-resolved. |
| OK-07 | Wire automated bead creation | When commitment is overdue + not backed: `bd create --title "[Oathkeeper] ..." --priority 2 --tags oathkeeper`. Store bead ID in commitment record. Transition status to `bead_created`. | OK-06 | S | Unverified expired commitments create beads automatically. |
| OK-08 | Add dry-run mode | `--dry-run` flag for scan and check-expired. Shows what would happen without mutations. Essential for testing automation. | OK-07 | S | `oathkeeper check-expired --dry-run` outputs actions without executing. |
| OK-09 | Enhance cron job | Update daily cron to run: (1) `scan --recent`, (2) `check-expired`. Add logging to file. Configure via `oathkeeper.toml`. | OK-07 | S | Cron runs full pipeline daily. Logs to `~/.local/share/oathkeeper/logs/`. |

### Phase 3: Integration (Week 3-4)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| OK-10 | Define Relay event schemas | Design event types: `oathkeeper.commitment.detected`, `oathkeeper.commitment.broken`, `oathkeeper.commitment.resolved`. JSON schema with commitment details, agent, timestamp. | None | S | Event schemas documented in `docs/relay-events.md`. |
| OK-11 | Implement Relay publishing | Add Relay client. Publish events on: new commitment detected (after grace period starts), broken promise (bead created), resolution. Config: `relay.enabled`, `relay.endpoint`. | OK-10 | L | Events published to Relay. Visible in Relay logs. |
| OK-12 | Add resolution webhook | HTTP endpoint or Relay subscription: receive confirmation that commitment was fulfilled externally. Update status to `resolved`. | OK-11 | M | External systems can mark commitments resolved. |

### Phase 4: Observability (Week 4-5)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| OK-13 | Expand stats command | `oathkeeper stats` outputs: total commitments, kept/broken ratio, breakdown by category, breakdown by agent, 7/30/90 day trends. | OK-05 | M | `oathkeeper stats` shows comprehensive metrics. |
| OK-14 | Add JSON/CSV export | `oathkeeper export --format json|csv`. Full commitment history for external analysis. | OK-13 | S | `oathkeeper export --format json > commitments.json` works. |
| OK-15 | Create stats dashboard | Markdown or HTML dashboard generated by `oathkeeper dashboard`. Shows trends, worst offenders, recent activity. | OK-13 | M | `oathkeeper dashboard` generates viewable report. |

### Phase 5: Hardening (Ongoing)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| OK-16 | Add verification backends | Extend backing verification: cron job check (grep crontab), state file patterns, optional git commit search. | OK-06 | M | Multiple verification strategies configurable. |
| OK-17 | Improve error handling | Graceful degradation when `bd` unavailable. Retry logic for Relay. Clear error messages. | OK-07, OK-11 | S | Oathkeeper doesn't crash on external failures. Errors logged clearly. |
| OK-18 | Add test suite | Unit tests for detector, integration tests for CLI, end-to-end test with mock transcript. | OK-08 | M | `go test ./...` passes. >70% coverage on core packages. |
| OK-19 | Write operational runbook | Document: installation, config options, troubleshooting, manual resolution workflow, metrics interpretation. | OK-15 | S | `docs/RUNBOOK.md` covers all operational scenarios. |

---

## 5. Recommended First Three Tasks

### 1️⃣ OK-01: Tune detector confidence threshold

**Why first:** Highest ROI. Reduces noise immediately. Every downstream feature benefits from cleaner data.

**Dispatch prompt:**
```
Read /home/chrote/athena/tools/oathkeeper and implement min_confidence config option.
Add `min_confidence` (float, default 0.7) to oathkeeper.toml schema.
Filter commitment candidates below threshold before SQLite insertion.
Log rejected candidates at debug level with their confidence scores.
Update `oathkeeper doctor` to report current threshold.
Test with existing transcripts, measure false positive reduction.
```

**Acceptance:**
- [ ] Config option parsed and respected
- [ ] Low-confidence commitments filtered
- [ ] Debug logging shows rejections
- [ ] CHANGELOG entry added

---

### 2️⃣ OK-02: Improve commitment prompt

**Why second:** Precision over recall. A well-tuned prompt reduces false positives at the source, before confidence filtering.

**Dispatch prompt:**
```
Read /home/chrote/athena/tools/oathkeeper, find the LLM classification prompt.
Improve it to distinguish:
(a) Agent commits to action ("I'll fix this") → TRACK
(b) Agent suggests to user ("You could add tests") → IGNORE  
(c) User requests action ("Please add logging") → IGNORE

Create test file with 15+ labeled examples (5 per category).
Verify prompt achieves >90% accuracy on test cases.
Document prompt changes in code comments.
```

**Acceptance:**
- [ ] Prompt clearly distinguishes three categories
- [ ] Test cases file exists with 15+ examples
- [ ] Accuracy measured and >90%
- [ ] CHANGELOG entry added

---

### 3️⃣ OK-03: Add commitment categories

**Why third:** Foundation for grace periods. Categories determine how long to wait before flagging.

**Dispatch prompt:**
```
Read /home/chrote/athena/tools/oathkeeper, find SQLite schema.
Add migration: new `category` column (TEXT, enum-like).
Valid values: explicit_promise, will_do, todo_mention, bug_acknowledged.
Update detector to classify category at detection time.
Update `oathkeeper list` output to show category column.
Add category filter: `oathkeeper list --category will_do`.
```

**Acceptance:**
- [ ] Schema migration applied cleanly
- [ ] New commitments have category
- [ ] `oathkeeper list` shows categories
- [ ] Filter flag works
- [ ] CHANGELOG entry added

---

## Sequencing Visualization

```
Week 1          Week 2          Week 3          Week 4          Week 5
────────────────────────────────────────────────────────────────────────
OK-01 ──┬──▶ OK-02 ──▶ OK-03 ──▶ OK-04 ──▶ OK-05
        │                                    │
        │                              OK-06 ◀┘
        │                                │
        │                          OK-07 ◀┘──▶ OK-08 ──▶ OK-09
        │                            │
        │                      OK-17 ◀┘
        │
OK-10 ──┼──────────────────▶ OK-11 ──▶ OK-12
        │
        └──────────────────────────────────▶ OK-13 ──▶ OK-14 ──▶ OK-15
                                               │
                                         OK-16 ◀┘
                                               │
                                         OK-18 ◀┘──▶ OK-19
```

---

## Risk Notes

1. **Relay integration (OK-11)** is the highest-risk item. May require understanding Relay internals that aren't documented yet. Consider stubbing with file-based events first.

2. **LLM dependency** for classification means costs and latency. Consider caching or local model fallback for high-volume transcripts.

3. **`bd` CLI availability** is assumed. Add graceful degradation early (OK-17) to prevent silent failures.

---

## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| False positive rate | ~40% (est.) | <10% | Manual audit of 50 commitments |
| Commitments auto-tracked | 0% | 100% | `oathkeeper stats` |
| Broken promises with beads | 0% | 100% | `bd list --tags oathkeeper` |
| Daily scan completion | Manual | Automated | Cron log check |
| Promise-keeping rate | Unknown | Tracked | `oathkeeper stats --trend` |

---

_Roadmap owner: Athena strategist session_
_Review cycle: Weekly until Phase 2 complete_
