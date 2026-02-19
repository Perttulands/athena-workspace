---
feature: centurion
last_updated: 2026-02-19
status: active
owner: athena
---

# Centurion — PRD

_Last updated: 2026-02-19_

## Purpose

Centurion is the **gate guard** of the Agora. He protects main. When code wants to merge, Centurion runs the gauntlet: tests, lint, Truthsayer scan, UBS scan. One decision: pass or fail. Nothing merges without his seal.

**One sentence:** Test-gated merge with semantic code review.

## Why This Exists

Agents produce code. Some of it is good. Some of it "passes tests" by rewriting the tests. Some of it has subtle bugs that mechanical checks miss. You need a guard who:

1. Runs all the mechanical checks (tests, lint, scans)
2. Does semantic review (is this actually correct?)
3. Makes a binary decision (merge or reject)
4. Has authority (nothing bypasses the gate)

## Current State

**Working:**
- Script: `centurion.sh` in athena workspace
- Runs: tests, truthsayer, basic checks
- Merge decision: pass/fail
- Lock file prevents concurrent merges

**Location:** `/home/chrote/athena/workspace/scripts/centurion.sh`

**Not yet:** semantic code review, conflict resolution

## What Centurion Does

1. **Runs test suites** — All tests must pass
2. **Runs Truthsayer** — No error-severity findings
3. **Runs linters** — Code style checks
4. **Makes decision** — Pass → merge. Fail → reject.
5. **Enforces exclusivity** — Lock prevents race conditions

## What Centurion Does NOT Do

1. **Write rules** — That's Senate
2. **Learn from history** — That's Learning Loop
3. **Track commitments** — That's Oathkeeper
4. **Handle dispatch** — That's Athena

## Target State

### Semantic Code Review

Beyond mechanical checks, Centurion should:
- Review the diff for correctness
- Check if tests actually test the code (not gaming)
- Identify subtle bugs that pass tests
- Flag suspicious patterns (e.g., removing assertions)

This requires Centurion to be an **intelligent agent**, not just a script.

### Merge Conflict Resolution

When branches conflict:
1. Centurion attempts automatic resolution
2. If ambiguous, escalates to Senate
3. Implements Senate verdict

### Quality Levels

| Level | Checks | When |
|-------|--------|------|
| **Quick** | Lint + fast tests | Pre-commit |
| **Standard** | Full tests + Truthsayer | PR merge |
| **Deep** | Standard + semantic review | Main merge |

## Definition of Done

1. ✅ Basic gate works (tests, truthsayer)
2. ✅ Lock file prevents races
3. ⬜ Semantic code review (agent-based)
4. ⬜ Test gaming detection
5. ⬜ Merge conflict resolution
6. ⬜ Senate escalation for ambiguous cases
7. ⬜ Quality level selection

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Truthsayer** | Centurion calls Truthsayer as one check. |
| **Senate** | Escalates ambiguous cases. Implements Senate merge verdicts. |
| **Athena** | Receives merge requests. Reports results. |
| **Learning Loop** | Gate results feed into run feedback. |

## Next Steps (Priority Order)

1. **Agent-based review** — Make Centurion an intelligent agent
2. **Test gaming detection** — Flag suspicious test modifications
3. **Quality levels** — Quick/Standard/Deep modes
4. **Conflict resolution** — Handle merge conflicts
5. **Senate integration** — Escalate ambiguous cases

## Technical Notes

- Current implementation: bash script (~200 lines)
- Target: Claude Code instance with code review skill
- Lock file: prevents concurrent merges on same repo

## Mythology

Centurion is a centaur — half horse, half warrior, all judgment. He stands at the gate to main, a bronze seal in one hand and a rejection stamp in the other. His eyes scan the diff like he's reading prophecy.

He doesn't care about your deadline. He doesn't care that "it works on my machine." He cares about the gate. The gate is sacred. Nothing passes that shouldn't.

When he stamps approval, the seal glows. When he rejects, the stamp leaves a mark that takes three passing runs to fade.
