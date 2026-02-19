---
feature: oathkeeper
last_updated: 2026-02-19
status: active
owner: athena
---

# Oathkeeper — PRD

_Last updated: 2026-02-19_

## Purpose

Oathkeeper is the **commitment tracker** of the Agora. He scans agent transcripts for promises — "I'll fix that," "I'll add tests," "that's an existing bug" — and verifies whether they were kept. If a commitment has no backing (no bead, no cron, no PR), Oathkeeper creates a bead to track it.

**One sentence:** Memory system that enforces agents keep their promises.

## Why This Exists

AI agents are pathological liars. Not malicious — they genuinely believe themselves in the moment. "I'll add error handling after this." "I'll come back and write the tests." They say it with confidence. Then the context window moves on and they forget.

Oathkeeper doesn't forget.

This is NOT:
- Code review (that's Centurion)
- Learning/feedback (that's Learning Loop)
- Bug scanning (that's Truthsayer)

This IS:
- A memory system for commitments
- Accountability for stated intentions
- The project manager who reads every transcript and follows up

## Current State

**Working:**
- CLI commands: `scan`, `list`, `stats`, `resolve`, `doctor`
- JSONL transcript parsing (OpenClaw format)
- Commitment detection (pattern matching + LLM classification)
- SQLite storage for commitments
- Integration with beads (`bd create`)

**Location:** `/home/chrote/athena/tools/oathkeeper`

**Repo:** `github.com/Perttulands/oathkeeper`

**Config:** `~/.config/oathkeeper/oathkeeper.toml`

## What Oathkeeper Does

1. **Scans transcripts** for commitments (explicit promises, TODOs, acknowledged bugs)
2. **Verifies backing** — Does a bead exist? A cron job? A state file?
3. **Creates beads** for unverified commitments via `bd create`
4. **Tracks resolution** — Was the commitment eventually kept?

## What Oathkeeper Does NOT Do

1. **Code review** — That's Centurion. Oathkeeper cares about words, not code.
2. **Quality feedback** — That's Learning Loop. Oathkeeper doesn't judge run quality.
3. **Real-time blocking** — Oathkeeper is async. Grace period, then check.
4. **Adversarial detection** — Not trying to catch malice, just forgetfulness.

## Target State

### Automated Daily Scan
- Cron job scans new transcripts
- New commitments detected → grace period starts
- After grace period → verify backing → create bead if missing

### Commitment Categories
| Category | Example | Grace Period |
|----------|---------|--------------|
| `explicit_promise` | "I'll fix that in the next step" | 1 hour |
| `will_do` | "I'll add tests later" | 24 hours |
| `todo_mention` | "TODO: handle edge case" | 7 days |
| `bug_acknowledged` | "That's an existing bug" | 24 hours |

### Relay Integration
- Oathkeeper sends commitment alerts via Relay
- Athena receives and can surface to Perttu
- Resolution confirmations flow back

### Sensitivity Tuning
Current detector is too aggressive (flags non-commitments). Target:
- `min_confidence: 0.7` or higher
- Fewer false positives on conversational text
- Clear distinction between "I'll do X" and "you could do X"

## Definition of Done

1. ✅ Core scanner works (transcript parsing, commitment detection)
2. ✅ CLI functional (`scan`, `list`, `stats`, `resolve`, `doctor`)
3. ✅ Config file support
4. ✅ Cron job scheduled (06:30 daily)
5. ⬜ Sensitivity tuned (fewer false positives)
6. ⬜ Automated bead creation working
7. ⬜ Grace period logic implemented
8. ⬜ Relay integration for alerts
9. ⬜ Stats dashboard (how many commitments kept vs broken)

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Athena** | Files transcripts that Oathkeeper scans. Receives commitment alerts. |
| **Beads** | Oathkeeper creates beads for unverified commitments. |
| **Relay** | Oathkeeper sends alerts through Relay. |
| **Learning Loop** | Orthogonal. LL tracks run quality, Oathkeeper tracks promises. |
| **Centurion** | Orthogonal. Centurion reviews code, Oathkeeper reviews words. |

## Next Steps (Priority Order)

1. **Tune detector sensitivity** — Reduce false positives
2. **Implement grace period logic** — Wait before flagging
3. **Wire automated bead creation** — `bd create` on unverified commitments
4. **Add Relay integration** — Alerts flow through backbone
5. **Build stats dashboard** — Track promise-keeping rate over time

## Mythology

Oathkeeper wears a red Spartan cloak — the only red in the Agora, so you always know when he's in the room. A bronze ledger strapped across his breastplate like a bandolier. A chain wrapped around one forearm. On his palm, the brand of the River Styx — which he presses onto fulfilled oaths like a receipt stamp from hell.

The ancient Greeks swore by the Styx, and even gods paid for breaking those oaths.

AI agents don't have divine consequences. So we built one.
