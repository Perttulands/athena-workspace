# Ludus Magnus — Implementation Roadmap

_Generated: 2026-02-19_
_Strategist: Opus_

---

## 1. Current State Summary

Ludus Magnus exists as a functional Go CLI with foundational capabilities:

| Component | Status | Notes |
|-----------|--------|-------|
| CLI binary | ✅ Working | `ludus-magnus` at `~/go/bin/` |
| Session management | ✅ Working | `quickstart init`, `training init` |
| Single lineage mode | ✅ Working | One prompt, iterative improvement |
| Four-lineage training | ✅ Working | Parallel competing lineages A/B/C/D |
| Run execution | ✅ Working | `run <session> --input "..."` |
| Manual evaluation | ✅ Working | `evaluate <artifact> --score N` |
| Basic iteration | ✅ Working | `iterate <session>` evolves prompts |
| Status/export | ✅ Working | View lineages, export winners |
| State persistence | ✅ Working | Local JSON file |

**What exists:** A human-in-the-loop prompt evolution system. User provides input, scores output, system mutates and repeats.

**What's missing:** Automation. The system requires manual inputs and manual scoring. There's no challenge generation, no automated evaluation, no integration with other Agora systems, and no production deployment pipeline.

---

## 2. Target State Summary

Per PRD, Ludus Magnus should be a **fully automated training ground**:

### Training Loop (Automated)
```
Generate challenge → Run N prompts → Score automatically → Select top K → Mutate → Repeat
```

### Required Capabilities

| Capability | Description |
|------------|-------------|
| **Challenge generation** | Synthetic tasks: feature, bug fix, refactor, review |
| **Tournament system** | N prompts compete on same challenge, automated |
| **Automated evaluation** | Correctness (tests), quality (Truthsayer), efficiency (time), style (Opus) |
| **Mutation operators** | Sophisticated prompt variation strategies |
| **Lineage tracking** | Which prompts descend from which (exists, needs verification) |
| **Integration** | Centurion (quality), Truthsayer (scanning), Learning Loop (selection) |
| **Production deployment** | Export winning prompts to Athena dispatch |

### Integration Points

- **Truthsayer:** Scan generated code for quality scoring
- **Centurion:** Use verification checks in evaluation
- **Learning Loop:** Feed trained prompts for task-based selection
- **Athena:** Deploy winning prompts to production dispatch

---

## 3. Gap Analysis

### Critical Gaps (Blocking Automation)

| Gap | Current | Target | Impact |
|-----|---------|--------|--------|
| **G1: Challenge Generation** | None. Manual input only. | Synthetic task generator for 4 types | Cannot run unattended training |
| **G2: Automated Evaluation** | Manual 1-10 scoring | Multi-criteria auto-scoring | Cannot scale past human attention |
| **G3: Truthsayer Integration** | None | Quality scoring via scan | Missing code quality signal |
| **G4: Test Execution** | None | Run tests, score pass/fail | No correctness signal |

### Important Gaps (Required for Full System)

| Gap | Current | Target | Impact |
|-----|---------|--------|--------|
| **G5: Tournament Orchestration** | 4 parallel lineages, manual eval | Automated tournament with ranking | Can't select winners at scale |
| **G6: Mutation Sophistication** | Basic iterate | Multiple mutation operators | Limited exploration of prompt space |
| **G7: Learning Loop Integration** | None | Feed trained prompts to LL | Training doesn't reach production |
| **G8: Production Export** | `export` command exists | Athena dispatch integration | Trained prompts sit unused |

### Minor Gaps (Polish)

| Gap | Current | Target | Impact |
|-----|---------|--------|--------|
| **G9: Lineage Visualization** | `status` shows history | Rich lineage tree view | Harder to understand evolution |
| **G10: Cost Tracking** | None | LLM cost per training run | Budget surprises |
| **G11: Checkpoint/Resume** | Unclear | Training can pause/resume | Long runs are fragile |

---

## 4. Implementation Roadmap

### Phase 1: Automated Evaluation Pipeline

Enable automated scoring so training can run unattended.

---

#### LM-001: Test Harness Integration

**Title:** Implement test execution within evaluation pipeline

**Description:** 
Add ability to run tests against generated code and incorporate pass/fail into scoring. The evaluation command should accept a `--tests` flag pointing to a test directory/command, execute tests, and include results in the evaluation score.

**Dependencies:** None

**Complexity:** M

**Files to modify/create:**
- `cmd/evaluate.go` — add test execution flag
- `internal/evaluation/test_runner.go` — new file for test execution
- `internal/evaluation/scorer.go` — incorporate test results

**Definition of Done:**
- [ ] `ludus-magnus evaluate <artifact> --tests "./run-tests.sh"` executes tests
- [ ] Test results (pass/fail/count) stored in evaluation record
- [ ] Correctness score computed from test pass rate
- [ ] Works with arbitrary test commands (shell script, `go test`, `pytest`)
- [ ] Unit tests for test runner module

---

#### LM-002: Truthsayer Integration

**Title:** Integrate Truthsayer scans into evaluation scoring

**Description:**
Call Truthsayer to scan generated code artifacts and incorporate findings into quality score. Requires Truthsayer binary available, handling of scan results, and mapping findings to numeric score.

**Dependencies:** LM-001 (scorer infrastructure)

**Complexity:** M

**Files to modify/create:**
- `internal/evaluation/truthsayer.go` — new file for Truthsayer integration
- `internal/evaluation/scorer.go` — add quality dimension

**Definition of Done:**
- [ ] `ludus-magnus evaluate <artifact> --truthsayer` runs Truthsayer scan
- [ ] Findings (error/warning/info counts) stored in evaluation record
- [ ] Quality score computed from Truthsayer findings
- [ ] Graceful handling if Truthsayer binary not available
- [ ] Integration test with sample code artifact

---

#### LM-003: Multi-Criteria Scorer

**Title:** Implement composite scoring with weighted criteria

**Description:**
Combine correctness (tests), quality (Truthsayer), efficiency (time), and manual style scores into a single composite score. Support configurable weights. This becomes the basis for automated selection.

**Dependencies:** LM-001, LM-002

**Complexity:** S

**Files to modify/create:**
- `internal/evaluation/composite.go` — new file for composite scoring
- `internal/config/weights.go` — scoring weight configuration

**Definition of Done:**
- [ ] Composite score computed from all available signals
- [ ] Weights configurable via session config or CLI flags
- [ ] Missing signals handled gracefully (partial scoring)
- [ ] Score breakdown visible in `status` output
- [ ] Unit tests for weight combinations

---

### Phase 2: Challenge Generation

Enable synthetic task creation so training doesn't require human inputs.

---

#### LM-004: Challenge Schema Definition

**Title:** Define challenge schema and types

**Description:**
Create the data structures for challenges. Four types: feature, bug_fix, refactor, review. Each challenge has a description, optional starter code, expected outcomes, and evaluation criteria.

**Dependencies:** None

**Complexity:** S

**Files to modify/create:**
- `internal/challenge/types.go` — challenge type definitions
- `internal/challenge/schema.go` — JSON schema for challenges
- `examples/challenges/` — sample challenges for each type

**Definition of Done:**
- [ ] Challenge struct defined with all required fields
- [ ] JSON schema documented
- [ ] 2+ example challenges per type (8 total)
- [ ] Challenges can be loaded from JSON files
- [ ] Unit tests for schema validation

---

#### LM-005: Challenge Generator

**Title:** Implement LLM-based challenge generation

**Description:**
Use an LLM to generate synthetic challenges given a domain/difficulty specification. Generator produces challenges matching the schema, with appropriate variety.

**Dependencies:** LM-004

**Complexity:** L

**Files to modify/create:**
- `cmd/challenge.go` — new CLI commands for challenge generation
- `internal/challenge/generator.go` — LLM-based generation
- `internal/challenge/prompts/` — generation prompts per type

**Definition of Done:**
- [ ] `ludus-magnus challenge generate --type feature --domain "web API"` works
- [ ] Generated challenges pass schema validation
- [ ] Challenges include starter code where appropriate
- [ ] Challenges include test cases or evaluation criteria
- [ ] Generated challenges are varied (no repetition within session)
- [ ] Unit tests for generator logic

---

#### LM-006: Challenge Library

**Title:** Implement persistent challenge library

**Description:**
Store generated and curated challenges in a library for reuse. Support tagging, difficulty levels, and random selection for training runs.

**Dependencies:** LM-004, LM-005

**Complexity:** M

**Files to modify/create:**
- `internal/challenge/library.go` — library management
- `cmd/challenge.go` — add list/add/remove commands
- `state/challenges/` — challenge storage location

**Definition of Done:**
- [ ] `ludus-magnus challenge add <file>` adds to library
- [ ] `ludus-magnus challenge list --type feature` lists challenges
- [ ] `ludus-magnus challenge random --type bug_fix` selects randomly
- [ ] Challenges tagged with type, difficulty, domain
- [ ] Library persists across sessions

---

### Phase 3: Tournament Automation

Enable fully automated training runs.

---

#### LM-007: Tournament Orchestrator

**Title:** Implement automated tournament execution

**Description:**
Run a full tournament: pull challenge, run all lineages, evaluate all outputs, rank results, select winners. Single command triggers entire cycle.

**Dependencies:** LM-003, LM-006

**Complexity:** L

**Files to modify/create:**
- `cmd/tournament.go` — new CLI commands
- `internal/tournament/orchestrator.go` — tournament logic
- `internal/tournament/ranking.go` — ranking algorithms

**Definition of Done:**
- [ ] `ludus-magnus tournament run <session>` executes one round
- [ ] All lineages run against same challenge
- [ ] All outputs evaluated with composite scorer
- [ ] Rankings computed and stored
- [ ] Winners identified per tournament
- [ ] Round history visible in status

---

#### LM-008: Selection and Evolution

**Title:** Implement automated winner selection and loser mutation

**Description:**
After tournament, automatically lock winners and evolve losers. Support different selection strategies (top-K, tournament selection, etc.).

**Dependencies:** LM-007

**Complexity:** M

**Files to modify/create:**
- `internal/tournament/selection.go` — selection strategies
- `internal/evolution/strategies.go` — evolution strategies
- `cmd/tournament.go` — add `--auto-evolve` flag

**Definition of Done:**
- [ ] Top-K selection implemented (keep top 2 of 4)
- [ ] Losers automatically mutated
- [ ] Selection strategy configurable
- [ ] Evolution preserves lineage history
- [ ] Dry-run mode shows what would change

---

#### LM-009: Training Loop Runner

**Title:** Implement continuous training loop

**Description:**
Run multiple tournament rounds unattended. Continue until convergence criterion met or round limit reached.

**Dependencies:** LM-007, LM-008

**Complexity:** M

**Files to modify/create:**
- `cmd/train.go` — new training command
- `internal/training/loop.go` — training loop logic
- `internal/training/convergence.go` — convergence detection

**Definition of Done:**
- [ ] `ludus-magnus train <session> --rounds 10` runs N rounds
- [ ] Progress logged per round
- [ ] Early stopping when scores converge
- [ ] Training can be interrupted and resumed (LM-011 dependency optional)
- [ ] Final report shows evolution over rounds

---

### Phase 4: Mutation Sophistication

Improve prompt exploration.

---

#### LM-010: Mutation Operator Library

**Title:** Implement diverse mutation operators

**Description:**
Current `iterate` is a black box. Implement explicit mutation operators: rephrase, add constraint, remove constraint, combine, specialize, generalize. Allow selection of operators.

**Dependencies:** None (can parallel with Phase 3)

**Complexity:** M

**Files to modify/create:**
- `internal/evolution/operators.go` — mutation operators
- `internal/evolution/prompts/` — operator-specific prompts
- `cmd/iterate.go` — add `--operator` flag

**Definition of Done:**
- [ ] 5+ mutation operators implemented
- [ ] Operators documented with expected effects
- [ ] `ludus-magnus iterate <session> --operator specialize` works
- [ ] Random operator selection as default
- [ ] Operator usage tracked in lineage history

---

### Phase 5: Integration and Deployment

Connect to Agora ecosystem.

---

#### LM-011: Checkpoint and Resume

**Title:** Implement training checkpoint/resume

**Description:**
Allow training to be paused and resumed. Critical for long runs and recovery from failures.

**Dependencies:** LM-009

**Complexity:** S

**Files to modify/create:**
- `internal/training/checkpoint.go` — checkpoint logic
- `state/checkpoints/` — checkpoint storage

**Definition of Done:**
- [ ] Training state checkpointed every N rounds
- [ ] `ludus-magnus train --resume <checkpoint>` continues
- [ ] Checkpoint includes all lineage and round state
- [ ] Corrupted checkpoint detection

---

#### LM-012: Learning Loop Integration

**Title:** Export trained prompts to Learning Loop

**Description:**
After training, winning prompts should be exported to Learning Loop for task-based selection. Define export format and integration contract.

**Dependencies:** LM-009

**Complexity:** M

**Files to modify/create:**
- `cmd/export.go` — enhance export for LL format
- `internal/export/learning_loop.go` — LL integration
- Documentation of integration contract

**Definition of Done:**
- [ ] `ludus-magnus export <session> --target learning-loop` works
- [ ] Export includes prompt, lineage, training stats
- [ ] Format matches Learning Loop import spec
- [ ] Integration tested with Learning Loop

---

#### LM-013: Cost Tracking

**Title:** Implement LLM cost tracking

**Description:**
Track token usage and estimated cost for each run, evaluation, and training session. Critical for budget management.

**Dependencies:** None

**Complexity:** S

**Files to modify/create:**
- `internal/cost/tracker.go` — cost tracking
- `cmd/status.go` — add cost display

**Definition of Done:**
- [ ] Token usage tracked per API call
- [ ] Cost estimated using model pricing
- [ ] `ludus-magnus status <session> --cost` shows total spend
- [ ] Cost included in training reports

---

#### LM-014: Production Dispatch Integration

**Title:** Deploy winning prompts to Athena dispatch

**Description:**
Enable direct deployment of trained prompts to Athena's dispatch templates. Include versioning and rollback.

**Dependencies:** LM-012

**Complexity:** L

**Files to modify/create:**
- `cmd/deploy.go` — new deployment command
- `internal/deploy/athena.go` — Athena integration
- Athena-side: template update API/mechanism

**Definition of Done:**
- [ ] `ludus-magnus deploy <session> --target athena` works
- [ ] Deployed prompt versioned
- [ ] Rollback to previous version supported
- [ ] Deployment logged and auditable
- [ ] Integration tested end-to-end

---

## 5. Recommended First Three Tasks

Based on dependency order and value delivery:

### 1️⃣ LM-001: Test Harness Integration

**Why first:** This is the foundation of automated evaluation. Without it, every subsequent automation feature requires human scoring. Unlocks the entire automation path.

**Dispatch prompt:**
```
Implement test execution in ludus-magnus evaluation pipeline.
Add --tests flag to evaluate command that runs a test command and 
incorporates pass/fail results into scoring. Create internal/evaluation/test_runner.go.
Support arbitrary shell commands. Add unit tests.
```

### 2️⃣ LM-004: Challenge Schema Definition  

**Why second:** This is the foundation of challenge generation. It's small, well-defined, and unblocks LM-005/LM-006. Can be done in parallel with LM-001.

**Dispatch prompt:**
```
Define challenge schema for ludus-magnus. Create internal/challenge/types.go
with Challenge struct supporting types: feature, bug_fix, refactor, review.
Include description, starter_code, expected_outcomes, evaluation_criteria fields.
Create 2 example challenges per type in examples/challenges/. Add schema validation.
```

### 3️⃣ LM-002: Truthsayer Integration

**Why third:** Once test harness exists (LM-001), adding Truthsayer gives a second evaluation dimension. This completes the automated quality signal.

**Dispatch prompt:**
```
Integrate Truthsayer scanning into ludus-magnus evaluation.
Create internal/evaluation/truthsayer.go that calls truthsayer binary,
parses findings, and computes quality score. Add --truthsayer flag to 
evaluate command. Handle missing binary gracefully. Add integration test.
```

---

## Appendix: Task Dependency Graph

```
LM-001 (Test Harness) ──┬──→ LM-003 (Composite Scorer) ──→ LM-007 (Tournament)
                        │                                         │
LM-002 (Truthsayer) ────┘                                         ↓
                                                            LM-008 (Selection)
LM-004 (Schema) ──→ LM-005 (Generator) ──→ LM-006 (Library) ──┘    │
                                                                    ↓
                                                            LM-009 (Training Loop)
                                                                    │
LM-010 (Mutations) ─────────────────────────────────────────────────┤
                                                                    ↓
                                                            LM-011 (Checkpoint)
                                                                    │
                                                            LM-012 (Learning Loop)
                                                                    │
                                                            LM-014 (Deploy)
                                                            
LM-013 (Cost) ─── Independent, implement anytime ───────────────────┘
```

---

## Appendix: Risk Notes

1. **Cost explosion:** Automated training runs many LLM calls. Implement LM-013 early or set hard limits.
2. **Challenge quality:** Generated challenges may be trivial or impossible. Manual curation layer may be needed.
3. **Evaluation brittleness:** Composite scoring needs tuning. Early runs should log all signals for calibration.
4. **Truthsayer availability:** Assumes Truthsayer binary exists and works. Need graceful degradation.

---

_Roadmap complete. Tasks are sequenced for incremental value delivery and minimal blocking._
