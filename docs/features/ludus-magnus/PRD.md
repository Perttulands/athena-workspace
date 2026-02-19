---
feature: ludus-magnus
last_updated: 2026-02-19
status: active
owner: athena
---

# Ludus Magnus — PRD

_Last updated: 2026-02-19_

## Purpose

Ludus Magnus is the **training ground** of the Agora. It trains agents through structured evaluation — synthetic challenges, model comparison, prompt evolution. Any agent type trains here before real deployment.

**One sentence:** Iterative prompt evolution through competition and selection.

## Why This Exists

Prompts matter. A good prompt can make a mediocre model perform well. A bad prompt makes even GPT-4 produce garbage. But how do you know which prompt is better?

Run them both. Compare results. Keep the winner. Iterate.

Ludus Magnus does this systematically:
1. Generate prompt variants
2. Run them on the same challenge
3. Score the outputs
4. Keep the winners, mutate, repeat

## Current State

**Framework exists:**
- Go CLI: `ludus-magnus`
- Lineage tracking
- Tournament system
- Basic evaluation

**Not yet:** Real training runs, production integration

**Location:** `/home/chrote/athena/tools/ludus-magnus`

**Repo:** `github.com/Perttulands/ludus-magnus`

## What Ludus Magnus Does

1. **Generates challenges** — Synthetic tasks for evaluation
2. **Runs tournaments** — Multiple prompts compete
3. **Scores outputs** — Quality, correctness, efficiency
4. **Evolves prompts** — Winners mutate, losers die
5. **Tracks lineages** — Which prompts descend from which

## What Ludus Magnus Does NOT Do

1. **Production dispatch** — That's Athena
2. **Template selection** — That's Learning Loop
3. **Code review** — That's Centurion
4. **Optimize for one task** — It's for generalizable improvement

## Target State

### Training Loop

```
Generate challenge → Run N prompts → Score → Select top K → Mutate → Repeat
```

### Challenge Types

| Type | What it tests |
|------|---------------|
| **Feature** | Can agent implement a spec? |
| **Bug fix** | Can agent diagnose and fix? |
| **Refactor** | Can agent improve code quality? |
| **Review** | Can agent find issues in code? |

### Evaluation Criteria

| Criterion | How scored |
|-----------|------------|
| **Correctness** | Tests pass |
| **Quality** | Truthsayer findings |
| **Efficiency** | Time to complete |
| **Style** | Opus review (qualitative) |

### Integration with Learning Loop

Ludus Magnus trains **prompts**. Learning Loop selects **which trained prompt to use**. They're complementary:

- Ludus Magnus: "This prompt variant is better for feature tasks"
- Learning Loop: "Given this specific task, use prompt variant X"

## Definition of Done

1. ✅ CLI exists (`ludus-magnus`)
2. ✅ Lineage tracking works
3. ⬜ Challenge generation implemented
4. ⬜ Tournament system running
5. ⬜ Evaluation scoring complete
6. ⬜ Mutation operators implemented
7. ⬜ Real training runs completed
8. ⬜ Trained prompts deployed to production

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Learning Loop** | Ludus trains prompts, LL selects among them |
| **Athena** | Consumes trained prompts for dispatch |
| **Centurion** | Evaluation uses Centurion's quality checks |
| **Truthsayer** | Evaluation uses Truthsayer scan |

## Next Steps (Priority Order)

1. **Challenge generation** — Create synthetic tasks
2. **Tournament system** — Run competitions
3. **Evaluation pipeline** — Score outputs consistently
4. **Mutation operators** — Prompt variation strategies
5. **First training run** — Real data on what works

## Technical Notes

- **Binary:** `~/go/bin/ludus-magnus`
- **State:** Lineages stored in `state/lineages/`
- **Cost:** Training is expensive (many LLM calls). Budget carefully.
- **Not RL:** This is structured evaluation, not reinforcement learning. The difference matters.

## Mythology

The Ludus Magnus was the gladiator training school next to the Colosseum in Rome. Warriors trained there before they fought for real.

In the Agora, agents train in Ludus Magnus before they ship production code. The arena is synthetic. The stakes are low. The lessons are real.

The training ground has sand that remembers — every bout leaves traces, and the patterns of victory emerge over time.
