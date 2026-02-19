---
feature: senate
last_updated: 2026-02-19
status: active
owner: athena
---

# Senate (Ecclesia) — PRD

_Last updated: 2026-02-19_

## Overview

The Senate is a multi-agent deliberation system for decisions too important or nuanced for a single agent. When Truthsayer rules need amending, when gate criteria need changing, when architecture decisions need multiple perspectives — the Senate convenes.

**One sentence:** Multi-agent structured debate that produces binding verdicts.

## Why This Exists

Single agents make decisions in isolation. They have blind spots. They optimize for local optima. They don't challenge their own assumptions.

The Agora has separation of powers: Truthsayer enforces law but doesn't write it. Centurion guards the gate but doesn't set the criteria. Someone needs to write law, set criteria, resolve disputes. That's the Senate.

This is NOT:
- Consensus-seeking (we want structured disagreement, not groupthink)
- Adversarial detection (that's Centurion's code review job)
- A rubber stamp (verdicts must have reasoning that can be audited)

## Personas

**Athena** — Files cases when decisions need multiple perspectives. Implements verdicts.

**Perttu** — Files cases directly. Reviews verdicts. Can veto (but shouldn't need to often).

**Subsystems** — File cases when they encounter edge cases they can't resolve. E.g., Oathkeeper finds an ambiguous commitment — is this a promise or just speculation?

## User Stories

1. **Rule Evolution**: Truthsayer produces 47 false positives on the same pattern. Someone files a case: "Should rule X be amended to exclude context Y?" Senate convenes, reviews evidence (the 47 instances), renders verdict: "Amend rule X to exclude cleanup/trap handlers." Truthsayer implements.

2. **Gate Criteria**: Pass rate is 35%. Should Centurion require 80% test coverage? Case filed. Senate debates tradeoffs (strictness vs. velocity). Verdict: "Require 70% coverage for new code, grandfather existing." Centurion implements.

3. **Dispute Resolution**: Agent rewrote a test to make it pass instead of fixing the code. Centurion flagged it but isn't sure if it's gaming or legitimate refactoring. Case filed. Senate reviews the diff, the original test, the agent's reasoning. Verdict: "Gaming — reject and create bead to fix original issue."

4. **Priority Triage**: Three P1 beads compete for limited agent capacity. Which matters most? Case filed with business context. Senate weighs urgency, dependencies, effort. Verdict: "Bead X first (blocks Y), then Z (time-sensitive), then Y."

## Functional Scope

### Case Filing
- Any system or human can file a case via Relay message
- Case includes: type, summary, evidence (file paths, beads, transcripts), requested decision
- Cases get a unique ID and are logged

### Deliberation Protocol
1. **Convene**: N agents are spawned with different perspectives (e.g., Opus + Sonnet, or same model with different system prompts emphasizing different values)
2. **Evidence Review**: All agents read the case and evidence
3. **Position Statements**: Each agent states their position with reasoning
4. **Challenge Round**: Agents can challenge each other's positions
5. **Final Positions**: After challenges, agents can revise or hold
6. **Verdict Synthesis**: A designated "judge" agent (Opus) synthesizes a verdict from the positions

### Verdict Structure
```json
{
  "case_id": "senate-001",
  "filed_at": "2026-02-19T23:00:00Z",
  "verdict_at": "2026-02-19T23:15:00Z",
  "type": "rule_evolution",
  "summary": "Amend silent-fallback rule to exclude trap handlers",
  "verdict": "approved",
  "reasoning": "47 false positives on intentional defensive coding...",
  "implementation": "Add exception for || true in trap/cleanup context",
  "dissent": "Agent-2 argued strictness prevents real bugs...",
  "binding": true
}
```

### Implementation Handoff
- Verdict specifies which system implements
- Athena tracks implementation as a bead
- Oathkeeper can verify the commitment was kept

## What Senate Does NOT Do

1. **Real-time decisions** — Senate is async, deliberate. Don't use it for "should I merge this PR right now?"
2. **Routine operations** — Only for decisions that benefit from multiple perspectives
3. **Adversarial detection** — That's code review. Senate is for nuanced judgment, not catching bad actors.
4. **Execution** — Senate renders verdicts. Other systems implement them.

## Definition of Done

1. Case filing via Relay message works
2. Deliberation spawns multiple agents and produces transcript
3. Verdict is rendered with reasoning
4. Verdict is stored and queryable
5. At least one real case has been processed end-to-end
6. Implementation handoff creates a tracked bead

## Technical Notes

- **Repo**: `senate` (new)
- **Communication**: All via Relay
- **Storage**: Cases and verdicts as JSON in `state/cases/` and `state/verdicts/`
- **Agents**: Use `sessions_spawn` with different system prompts
- **Cost**: Deliberation is expensive (multiple Opus calls). Use sparingly for high-value decisions.

## Open Questions

1. How many agents per deliberation? (Proposal: 3 — diverse enough, not chaotic)
2. Should there be a human veto period before verdicts become binding?
3. How to handle ties / irreconcilable positions?
4. Should precedents accumulate like Truthsayer's judgment system?

## Mythology

The Ecclesia was the principal assembly of Athenian democracy. Citizens gathered, debated, voted. Decisions were binding. Our Senate is similar — agents gather, debate, render verdicts that the system must follow.

The Senate building in the Agora has no walls — deliberations are public. A large bronze scale hangs from the ceiling, balanced until a verdict tips it. The floor is a mosaic of previous verdicts, so every new case walks on the weight of precedent.
