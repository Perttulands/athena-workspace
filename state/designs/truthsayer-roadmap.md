# Truthsayer Implementation Roadmap

_Generated: 2026-02-19_
_Strategist: Opus_

---

## 1. Current State Summary

**What exists and works:**

| Component | Status | Notes |
|-----------|--------|-------|
| Core scanner | ✅ Working | 88 rules across Go, JS/TS, Python, Bash, config files |
| AST analysis | ✅ Working | tree-sitter (JS/TS/Python), go/ast (Go) |
| CLI commands | ✅ Working | `scan`, `check`, `watch`, `rules`, `doctor` |
| Pre-commit hooks | ✅ Working | `truthsayer hook install .` |
| CI integration | ✅ Working | GitHub Actions workflow generation |
| JSON output | ✅ Working | `--format json` flag |
| Configuration | ✅ Working | `.truthsayer.toml` |

**Architecture:**
```
truthsayer scan . → findings (violations) → block/pass (binary)
```

The scanner is deterministic and binary: it reports violations or it doesn't. No contextual judgment, no precedent system, no learning.

---

## 2. Target State Summary

**Per PRD and JUDGMENT.md, Truthsayer needs:**

```
scan → findings → judge (LLM) → verdicts → action
                      ↑              ↓
               precedents.json   law-updates.md
                                      ↓
                               Senate integration
```

**Required capabilities:**

1. **`truthsayer judge` command** — Takes findings, applies context, produces verdicts (guilty/not-guilty/advisory)
2. **Precedent system** — Stores accumulated judgments in `precedents.json`, retrieves for matching patterns
3. **High-confidence auto-apply** — Precedents with confidence >0.9 skip LLM calls entirely
4. **LLM integration** — Claude Haiku for cost-efficient judgment calls
5. **Law update proposals** — Auto-generate rule amendments when patterns consistently ruled one way
6. **Senate integration** — Amendments flow back from Senate verdicts into rules
7. **Cost control** — <$0.01 per commit after warmup period

**Pending Senate verdict:** `quick-1771535739` requires amending `silent-fallback` for trap contexts.

---

## 3. Gap Analysis

| Target Feature | Current State | Gap |
|----------------|---------------|-----|
| `truthsayer judge` command | Does not exist | **Full implementation needed** |
| Precedent storage (`precedents.json`) | Does not exist | **Schema + read/write logic needed** |
| Precedent matching | Does not exist | **Pattern hashing + lookup needed** |
| LLM integration | Does not exist | **Claude API client + prompts needed** |
| Verdict types | Binary only | **Three-tier verdict system needed** |
| Context extraction | Not in findings | **±10 lines source context needed** |
| Confidence scoring | Does not exist | **Scoring + decay logic needed** |
| High-confidence auto-apply | Does not exist | **Bypass logic needed** |
| Law update proposals | Does not exist | **Detection + generation needed** |
| Senate integration | Does not exist | **Rule amendment parsing needed** |
| Cost tracking | Does not exist | **Token counting + budget logic needed** |
| Pre-commit judgment flow | Scan only | **Hook needs judgment integration** |

**Technical debt:**
- Senate verdict `quick-1771535739` is pending — rule needs amendment for trap contexts

---

## 4. Implementation Roadmap

### Phase 1: Foundation

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-001** | Implement Senate verdict quick-1771535739 | Amend `silent-fallback` rule to recognize `\|\| true` in trap/cleanup contexts as intentional. Add trap-context detection to Bash rule. | None | S | Rule passes `|| true` inside trap handlers; test case exists; rule doc updated |
| **TS-002** | Define precedent schema | Create `pkg/precedent/schema.go` with Precedent struct matching JUDGMENT.md spec. Include JSON marshaling, validation, pattern hash function. | None | S | Struct exists; can serialize/deserialize; has validation; unit tests pass |
| **TS-003** | Implement precedent storage | Create `pkg/precedent/store.go` — file-based store for `precedents.json`. Methods: Load, Save, Get, Put, Archive (90-day prune). | TS-002 | M | Store persists to disk; CRUD operations work; pruning tested |

### Phase 2: Context & Matching

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-004** | Extract source context for findings | Extend findings to include ±10 lines of source code around the violation. Add `Context` field to Finding struct. | None | S | Findings include source context; works for all 5 languages |
| **TS-005** | Implement pattern hashing | Create hash function that normalizes code patterns for precedent matching (strips variable names, normalizes whitespace). | TS-002 | M | Same logical patterns produce same hash; variable renames don't affect hash |
| **TS-006** | Implement precedent lookup | Add `Match(finding) → []Precedent` to store. Returns matching precedents sorted by confidence. Uses pattern hash + rule ID. | TS-003, TS-005 | M | Lookup returns matches; respects confidence threshold; benchmarks <10ms |

### Phase 3: LLM Integration

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-007** | Create LLM client | Add `pkg/llm/client.go` — thin wrapper for Claude API (Haiku). Handle auth, retries, rate limiting. | None | S | Client calls Claude; handles errors; respects rate limits |
| **TS-008** | Design judgment prompt | Create prompt template for judgment calls. Input: finding, context, rule description, existing precedents. Output: verdict + reasoning + suggested precedent. | None | S | Prompt template exists; tested against sample findings; verdicts are parseable |
| **TS-009** | Implement LLM judgment call | Create `pkg/judge/llm.go` — calls LLM with finding, parses response into Verdict struct. | TS-007, TS-008 | M | Can judge a finding; returns structured verdict; handles malformed responses |

### Phase 4: Judge Command

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-010** | Implement `truthsayer judge` command | New CLI command. Reads findings JSON, applies precedents, calls LLM for unknowns, outputs verdicts JSON. | TS-004, TS-006, TS-009 | L | Command runs; produces verdicts; respects precedents; creates new precedents |
| **TS-011** | Implement confidence updates | When same pattern re-judged, update confidence score. Increment on match, decay on override. | TS-003, TS-010 | S | Confidence increases on repeat rulings; resets on human override |
| **TS-012** | Implement auto-apply for high-confidence | Skip LLM when precedent confidence >0.9. Apply cached verdict directly. | TS-010, TS-011 | S | High-confidence precedents bypass LLM; cost metrics show reduction |

### Phase 5: Pre-commit Integration

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-013** | Integrate judgment into pre-commit hook | Update hook to run scan → judge pipeline. Block on guilty, pass on not-guilty/advisory. | TS-010 | M | Hook runs judge; blocks guilty verdicts; passes others; records precedents |
| **TS-014** | Add advisory tracking | Advisory verdicts create tech debt entries. Write to `.truthsayer-debt.json` with finding + reasoning. | TS-010 | S | Advisories logged; debt file accumulates; can be listed with CLI |

### Phase 6: Law Evolution

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-015** | Detect consistent ruling patterns | Track when same pattern is judged 10+ times the same way. Flag as law update candidate. | TS-003, TS-010 | M | Detection works; candidates logged; threshold configurable |
| **TS-016** | Generate law update proposals | Create `law-updates.md` with proposed rule changes. Include pattern, current rule, suggested amendment, evidence. | TS-015 | M | Proposals generated; format suitable for Senate review; includes evidence |
| **TS-017** | Parse Senate verdicts | Read Senate verdict files. Extract rule amendments. Apply to rule configuration. | None | M | Can parse verdict format; extracts amendments; validates syntax |
| **TS-018** | Apply rule amendments | When Senate approves, update rule logic or add exception. May require rule code changes or config updates. | TS-017 | L | Amendments apply; rules behave differently post-amendment; audit trail exists |

### Phase 7: Cost Control & Polish

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **TS-019** | Implement cost tracking | Track LLM token usage per judgment. Log to metrics file. Add `--budget` flag to cap spend. | TS-009 | S | Tokens counted; costs logged; budget enforcement works |
| **TS-020** | Batch similar findings | Group findings by rule+pattern before LLM call. Judge as batch to reduce API calls. | TS-010 | M | Batching reduces calls; verdicts correctly distributed; cost measurably lower |
| **TS-021** | Warmup mode | Add `truthsayer warmup <repo>` command. Runs scan+judge on entire repo to build precedent base. | TS-010 | S | Command exists; builds precedents; reports statistics |
| **TS-022** | Integration tests | End-to-end tests for scan→judge→verdict pipeline. Include mock LLM, precedent scenarios. | TS-010, TS-013 | M | E2E tests pass; cover happy path + edge cases; CI runs them |

---

## 5. Recommended First Three Tasks

Based on dependencies, value delivery, and risk reduction:

### 1. TS-001: Implement Senate verdict quick-1771535739
**Why first:** Pending Senate decision needs action. Small scope, immediate value, unblocks future Senate integration patterns. Proves the amendment workflow before automating it.

**Dispatch prompt:**
> Amend the `silent-fallback` rule in Truthsayer to recognize `|| true` in trap/cleanup contexts as intentional. Detect when the violation is inside a Bash trap handler and mark it as acceptable. Add test cases for trap contexts. Update rule documentation.

### 2. TS-002 + TS-003: Precedent schema and storage (combine as one bead)
**Why second:** The precedent system is the foundation of judgment. Schema is small; storage is the first integration point. Doing these together is natural.

**Dispatch prompt:**
> Create the precedent system for Truthsayer: 1) Define `pkg/precedent/schema.go` with Precedent struct per JUDGMENT.md spec (rule, pattern, verdict, reasoning, confidence, seen_count, first_seen, last_seen, repos). Include JSON marshaling and validation. 2) Implement `pkg/precedent/store.go` with file-based storage. Methods: Load, Save, Get, Put, Archive (prune entries with 0 hits in 90 days). Write unit tests for both.

### 3. TS-004: Extract source context for findings
**Why third:** Judgment requires context. This task is independent and enables parallel work on LLM prompts. Small scope, no dependencies on precedent work.

**Dispatch prompt:**
> Extend Truthsayer findings to include source context. Add a `Context` field to the Finding struct containing ±10 lines around the violation. Update all scanner backends (Go, JS/TS, Python, Bash, config) to populate this field. Ensure JSON output includes context. Write tests verifying context extraction.

---

## Dependency Graph

```
                    ┌─────────┐
                    │ TS-001  │ (Senate verdict - standalone)
                    └─────────┘

┌─────────┐         ┌─────────┐
│ TS-002  │────────▶│ TS-003  │
│ Schema  │         │ Store   │
└─────────┘         └────┬────┘
                         │
                    ┌────▼────┐         ┌─────────┐
                    │ TS-006  │◀────────│ TS-005  │
                    │ Lookup  │         │ Hash    │
                    └────┬────┘         └─────────┘
                         │
                         ▼
┌─────────┐    ┌─────────────────┐    ┌─────────┐
│ TS-004  │───▶│     TS-010      │◀───│ TS-009  │
│ Context │    │  Judge Command  │    │ LLM Call│
└─────────┘    └───────┬─────────┘    └────▲────┘
                       │                   │
                       │              ┌────┴────┐
                       │              │ TS-007  │◀── TS-008
                       │              │ Client  │    Prompt
                       │              └─────────┘
                       ▼
               ┌───────────────┐
               │    TS-013     │
               │  Pre-commit   │
               └───────┬───────┘
                       │
                       ▼
         ┌─────────────────────────┐
         │  Phase 6: Law Evolution │
         │  TS-015 → TS-016 → ...  │
         └─────────────────────────┘
```

---

## Success Metrics

| Metric | Target | Measurement Point |
|--------|--------|-------------------|
| Cost per commit (after warmup) | <$0.01 | TS-019 |
| Precedent hit rate (after warmup) | >80% | TS-021 |
| False positive rate | <5% | TS-022 |
| Judgment latency (cached) | <100ms | TS-012 |
| Judgment latency (LLM) | <3s | TS-009 |

---

## Notes

- **Model choice:** Use Claude Haiku for cost efficiency. Reserve Sonnet for complex judgments if Haiku accuracy is insufficient.
- **Precedent location:** Store in repo root as `.truthsayer/precedents.json` or global user cache depending on scope.
- **Senate integration:** Assumes Senate verdict format is documented elsewhere. TS-017 may need coordination with Senate maintainers.
- **Risk:** Pattern hashing (TS-005) is subtle. Wrong hashing = wrong precedent matches. Invest in test coverage.
