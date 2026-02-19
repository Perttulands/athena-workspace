# The Agora — System Architecture

_Last updated: 2026-02-19_

## Overview

The Agora is a modular AI agent system. Each component has one job, communicates through Relay, and evolves independently. The mythology isn't decoration — it's the naming scheme, the mental model, and the reason anyone remembers what does what.

## Systems

### 🦉 Athena — The Orchestrator

**Job:** Decompose work into beads, dispatch agents, watch progress, deliver results.

Athena is the brain. She decides what needs doing, who does it, and when it's done. She talks to every other system through Relay. The dispatch scripts, templates, and coordination logic all live here.

**Repo:** `athena` (workspace)

---

### 📡 Relay (Hermes) — The Nervous System

**Job:** Carry every message between every agent.

All agent-to-agent communication goes through Relay. Not some of it — all of it. Dispatch commands, gate results, status updates, Senate deliberations. Relay is the backbone that makes the system a system instead of a collection of scripts.

**Repo:** `relay`

---

### ⚔️ Centurion — The Gate Guard

**Job:** Protect main. Decide merge or reject.

Centurion guards the branch. He runs the full gauntlet: tests, lint, Truthsayer scan, UBS scan. One decision: pass or fail. Nothing merges without his seal.

**Future:** Merge conflict resolution — not just gatekeeping but actively resolving when branches collide.

**Repo:** `athena` (centurion.sh) — may become standalone when scope expands.

---

### 🔍 Truthsayer — The Scanner

**Job:** Find bugs and bad patterns in code.

88 rules across 5 languages. AST-level analysis via tree-sitter. Catches what linters miss: swallowed errors, mock leakage, silent fallbacks, missing timeouts. A tool — not a gate. Centurion calls it. Humans call it. CI calls it.

Truthsayer enforces the law. He doesn't write it. Rule evolution happens in the Senate.

**Repo:** `truthsayer`

---

### ⚖️ Oathkeeper — The Commitment Tracker

**Job:** Make sure agents (especially Athena) stick to their own plans and don't lose track of discovered bugs.

A memory system for commitments. Agents say things in conversation: "I'll fix that in the next step." "We should refactor this later." "That's an existing bug." Plans get made and then evaporate. Bugs get found mid-work and dismissed. Oathkeeper reads transcripts, finds those moments, and checks: did it become a bead? A cron job? A PR? If not, Oathkeeper creates the bead.

Not learning. Not quality feedback. Not code review. The closest human analogy: a project manager who reads every meeting transcript and follows up on every action item. An enforcer of your own stated intentions.

**Repo:** `oathkeeper`

---

### 🔄 Learning Loop (Ouroboros) — The Feedback Engine

**Job:** Make the system improve over time.

Collects feedback from every run. Scores templates and models. Detects failure patterns. Recommends the best dispatch configuration. The Opus judge adds qualitative assessment — not just "did it pass" but "is the code actually good."

Four nested loops: per-run → hourly scoring → daily refinement → weekly strategy.

**Repo:** `learning-loop`

---

### 🏟️ Ludus Magnus — The Training Ground

**Job:** Reinforcement learning for agents.

Synthetic challenges, structured evaluation, model comparison. Any agent — coding, research, analysis — trains here before real deployment. Different from Learning Loop: LL improves *selection* (which agent/template for which task), LM improves *agents themselves* (which prompts/techniques make an agent better at a task type).

**Repo:** `ludus-magnus`

---

### 👁️ Argus — The Watchdog

**Job:** Keep infrastructure alive.

Monitors every 5 minutes. Kills orphan processes. Restarts failed services. Files problem beads. The ops autopilot that fixes things before you wake up.

**Repo:** `argus`

---

### 🏛️ Athena Web (The Loom Room) — The Dashboard

**Job:** Visualize all work.

Web interface for beads — status, history, threads. The tapestry view where you stand to see everything at once.

**Repo:** `athena-web`

---

### 🏛️ Senate (Ecclesia) — The Deliberation Body

**Job:** Multi-agent deliberation on decisions too important for one agent.

The Senate convenes when a decision needs multiple perspectives. Not consensus-seeking — structured debate with a binding verdict. Multiple agents argue positions, evidence is presented, a decision is rendered.

**Scope:**

| Domain | Examples |
|--------|----------|
| **Rule evolution** | Amend Truthsayer rules based on false positive patterns. Add new rules. Retire obsolete ones. |
| **Gate criteria** | What should Centurion require for merge? Coverage thresholds? Mandatory checks? |
| **Architecture** | Split or merge services. API design decisions. Technology choices. |
| **Priorities** | When multiple beads compete for resources, which matters most? |
| **Dispute resolution** | Agent rewrote a test to game the gate — is this acceptable? Unclear Oathkeeper findings. |
| **Commitment patterns** | What counts as a promise in Oathkeeper's vocabulary? |

**Process:**
1. A case is filed (by any system, or by Perttu)
2. Senate convenes: multiple agents (different models/perspectives) review evidence
3. Structured debate: positions stated, challenged, defended
4. Verdict rendered with reasoning
5. Decision is binding — implemented by the relevant system

**Repo:** TBD (new repo: `senate`)

---

## How They Connect

```
Perttu
  │
  ▼
Athena (orchestrator)
  │
  ├──[Relay]──▶ Agent (codex/claude) ──▶ work done
  │                                          │
  │              ┌───────────────────────────┘
  │              ▼
  ├──[Relay]──▶ Centurion (gate) ──calls──▶ Truthsayer (scan)
  │              │                          tests, lint, UBS
  │              ▼
  │            merge or reject
  │
  ├──[Relay]──▶ Oathkeeper ──▶ scans transcripts ──▶ creates beads
  │
  ├──[Relay]──▶ Learning Loop ──▶ feedback ──▶ better dispatch
  │
  ├──[Relay]──▶ Ludus Magnus ──▶ train agents ──▶ better agents
  │
  ├──[Relay]──▶ Argus ──▶ monitors ──▶ heals
  │
  └──[Relay]──▶ Senate ──▶ deliberates ──▶ binding decisions
                              ▲
                              │
                   cases from any system
```

**Relay is load-bearing.** Every arrow is a Relay message. The dispatch scripts dissolve into messages. This is the target architecture.

## What's Built vs What's Designed

| System | Status |
|--------|--------|
| Athena (dispatch) | ✅ Working — bash scripts, needs Relay migration |
| Relay | ✅ Binary built — not yet the backbone, used minimally |
| Centurion | ✅ Working — bash script in athena |
| Truthsayer | ✅ Working — Go binary, 88 rules, 5 languages |
| Oathkeeper | ✅ Binary built — not automated, needs cron/Relay wiring |
| Learning Loop | ✅ Scripts built — not yet processing real runs |
| Ludus Magnus | ⚡ Framework exists — no real training runs yet |
| Argus | ✅ Working — monitors every 5 min |
| Athena Web | ⚠️ Built but unstable — service tends to die |
| Senate | 📋 Concept — needs design and implementation |

## Design Principles

1. **One job per system.** If you can't explain it in one sentence, split it.
2. **Communicate through Relay.** No direct calls, no arcane scripts. Messages.
3. **Evolve independently.** Each repo ships on its own schedule.
4. **Separation of powers.** Truthsayer enforces law, Senate writes law, Centurion guards the gate. No system judges its own work.
5. **Mythology is the architecture.** The names aren't cute labels — they're mental models that make the system legible.
