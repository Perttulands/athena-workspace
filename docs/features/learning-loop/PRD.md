---
feature: learning-loop
last_updated: 2026-02-19
status: active
owner: athena
---

# Learning Loop (Ouroboros) — PRD

_Last updated: 2026-02-19_

## Purpose

Learning Loop is the **feedback engine** of the Agora. Every agent run generates data: what template was used, what model, how long, did tests pass, did Truthsayer find anything. Learning Loop collects this, scores templates, detects failure patterns, and feeds insights back into dispatch.

**One sentence:** The system improves by using itself.

## Why This Exists

We dispatched 100+ agent runs. 19% passed verification. That's not an AI problem — that's a "nobody learns from the last disaster" problem.

The Learning Loop fixes that. Every run — success, partial pass, spectacular failure — generates a feedback record. The prompts that produce passing code get used more. The prompts that produce garbage get evolved or replaced.

## Current State

**Working:**
- Scripts: `feedback-collector.sh`, `score-templates.sh`, `select-template.sh`, `detect-patterns.sh`, `retrospective.sh`
- 92 feedback records processed
- 91 runs scored, 35% pass rate (up from 19%)
- Cron job scheduled (07:00 daily)

**Location:** `/home/chrote/athena/tools/learning-loop`

**Repo:** `github.com/Perttulands/learning-loop`

## What Learning Loop Does

1. **Collects feedback** from run records (outcome, duration, signals)
2. **Scores templates** by pass rate, retry rate, timeout rate
3. **Detects patterns** — What keeps failing? Which agents struggle where?
4. **Recommends templates** — Best template for task type
5. **Generates retrospectives** — What's improving, what's not

## What Learning Loop Does NOT Do

1. **Make dispatch decisions** — That's Athena. LL recommends, Athena decides.
2. **Modify templates directly** — LL proposes, human/Athena approves.
3. **Judge code quality** — That's Truthsayer + Centurion.
4. **Track commitments** — That's Oathkeeper.

## Target State

### Four Nested Loops

| Loop | Frequency | What Happens |
|------|-----------|--------------|
| **Per-run** | Immediate | Feedback extracted, stored |
| **Hourly** | Every hour | Scores updated, patterns detected |
| **Daily** | Every day | Retrospective generated, recommendations updated |
| **Weekly** | Every week | Strategy review, template refinement proposals |

### Opus Judge

Current scoring is mechanical: did tests pass? Target state adds qualitative judgment:

- Opus reviews code produced by run
- Rates: correctness, style, maintainability
- Identifies: did agent take shortcuts? Game tests? Miss edge cases?

This is NOT the same as Truthsayer (static rules). This is "is the code actually good?"

### Template Refinement

When a template consistently underperforms:
1. Learning Loop detects the pattern
2. Proposes refinement (modify prompt, add constraints)
3. Athena reviews and approves
4. Updated template enters rotation

### Dispatch Integration

Target: `select-template.sh` is called by dispatch automatically:

```bash
TEMPLATE=$(./scripts/select-template.sh feature)
./dispatch.sh $BEAD $REPO $AGENT "$(cat templates/$TEMPLATE.md)"
```

## Definition of Done

1. ✅ Feedback collection works
2. ✅ Template scoring works (35% pass rate tracked)
3. ✅ Pattern detection works
4. ✅ Retrospective generation works
5. ✅ Cron job scheduled
6. ⬜ Opus judge integrated (qualitative assessment)
7. ⬜ Dispatch integration (auto-select best template)
8. ⬜ Template refinement workflow (propose → review → deploy)
9. ⬜ Weekly strategy reports

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Athena** | Consumes recommendations. Reviews refinement proposals. |
| **Dispatch** | Calls select-template to choose best prompt. |
| **Truthsayer** | Findings are one signal in feedback (did scan pass?). |
| **Centurion** | Gate result is primary signal (did merge pass?). |
| **Ludus Magnus** | Trains individual agents. LL trains the selection system. |

## Next Steps (Priority Order)

1. **Dispatch integration** — Auto-select template
2. **Opus judge** — Qualitative code review on samples
3. **Refinement workflow** — Propose → review → deploy cycle
4. **Weekly strategy** — Higher-level insights
5. **Delta alerts** — Notify when pass rate drops significantly

## Metrics

Current state:
- **Pass rate:** 35% (target: 70%+)
- **Runs processed:** 91
- **Feedback records:** 92
- **Templates scored:** Multiple (see `state/scores/template-scores.json`)

## Mythology

There's a bronze serpent in the Agora, coiled in a circle, biting its own tail. Where the teeth meet flesh, the organic scales become circuit board. Flowers grow from the bite point — fiber optic blooms. It's the ouroboros. Perpetual self-renewal.

Every ending feeds the next beginning. Every failure feeds the next success.

That's the whole idea. That's the serpent eating its tail.
