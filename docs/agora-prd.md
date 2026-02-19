# The Agora — System PRD

_Source of truth for what this system is, why it exists, and what done looks like._

_Last updated: 2026-02-19_

---

## What Is This

A system where one person and one AI operate a software factory. Work goes in as ideas, comes out as shipped code. The system gets better at this over time without manual tuning.

The Agora is not a framework, not a platform, not a product you install. It's a living architecture — a set of intelligent agents, each with a clear job, talking to each other through a shared nervous system. Most of them are Claude Code or Codex instances with specialized skills and custom configs. The bash scripts and cron jobs that exist today are scaffolding toward that target.

## Problems It Solves

1. **One person can't build at the scale they think at.** Perttu has more ideas than hands. The system turns intent into execution without requiring him to micromanage every step.

2. **AI agents are unreliable without structure around them.** An agent with no gate ships garbage. An agent with no accountability forgets its own promises. An agent with no feedback never improves. The Agora provides the structure.

3. **Quality degrades when you move fast without gates.** Speed without rigor is just creating debt faster. Centurion ensures nothing reaches main that hasn't been reviewed — not just tested, but understood.

4. **Knowledge and commitments get lost between sessions.** Every agent wakes up fresh. Plans made in one session evaporate by the next. Oathkeeper catches what falls through the cracks.

5. **You can't improve what you don't measure.** Learning Loop closes the feedback loop. What worked? What didn't? What should we try differently? Without this, you're guessing forever.

6. **Complex decisions need more than one perspective.** A single agent has blind spots. The Senate provides structured deliberation for decisions where nuance matters.

---

## The Systems

### 🦉 Athena — The Orchestrator

**Why she exists:** Someone has to be the brain. Decompose work, pick the right agent, watch progress, deliver results, and — critically — be proactive. Athena doesn't wait to be told. She notices what needs doing, surfaces issues, suggests priorities, anticipates problems.

**What she does:**
- Proactively identifies work and surfaces it to Perttu
- Decomposes tasks into dispatchable beads
- Selects agent, template, and model for each task (informed by Learning Loop)
- Tracks progress and delivers results

**What she does NOT do:**
- Write code (she dispatches agents who do)
- Make final decisions on what to build (that's Perttu)
- Judge output quality (that's Centurion)

**Implementation:** The OpenClaw main session. Talks through Relay to all other systems.

**Definition of done:** Athena can take a vague idea from Perttu, break it into beads, dispatch agents, track them to completion, and deliver the result — without Perttu managing the process.

---

### 📡 Relay (Hermes) — The Nervous System

**Why it exists:** Right now agents are launched via bash scripts into tmux sessions. That's fragile, opaque, and breaks constantly. Relay replaces arcane dispatch scripts with a proper CLI and message-based coordination. It's the backbone that makes the system a system.

**What it does:**
- Carries messages between any two agents
- Provides a CLI for dispatch (`relay send`, not custom bash per operation)
- Guarantees zero message loss

**What it does NOT do:**
- Make decisions about what messages mean (it's a postman)
- Execute tasks
- Replace OpenClaw's channel messaging (Telegram, etc.)

**Implementation:** Go binary. Filesystem-based message passing.

**Definition of done:** Every agent-to-agent interaction goes through Relay. No more dispatch-specific bash scripts. A new agent can be added by subscribing to Relay topics, not by editing shell scripts.

---

### ⚔️ Centurion — The Quality Gate

**Why it exists:** Speed without rigor creates debt. Centurion is the gate that ensures nothing reaches main without being reviewed — not just mechanically checked, but intelligently understood.

**What it does:**
- Runs the full quality gauntlet: tests, lint, Truthsayer scan, UBS
- Performs semantic code review — a Claude Code/Codex instance that reads the diff and understands the code
- Makes a reasoned merge/reject decision with explanation
- Future: resolves merge conflicts

**What it does NOT do:**
- Write or fix code (separate agents do that)
- Set quality standards (that's the Senate)
- Run without an LLM — the mechanical checks are inputs, the review is intelligent

**Implementation:** Today: `centurion.sh` (bash, mechanical checks only). Target: Claude Code instance with a code review skill, calling Truthsayer and test runners as tools.

**Definition of done:** Centurion reviews every PR with both mechanical checks and semantic understanding. His merge/reject decisions include reasoning. False positive rate is low enough that his rejections are trusted.

---

### 🔍 Truthsayer — The Scanner

**Why it exists:** Linters catch syntax. Truthsayer catches lies — the patterns where code pretends everything is fine while hiding failures. Swallowed errors, mock leakage, silent fallbacks, missing timeouts.

**What it does:**
- Scans code for bugs and anti-patterns across 5 languages
- 88 rules, AST-level analysis via tree-sitter
- Works standalone — anyone can `go install` and use it in their own CI

**What it does NOT do:**
- Make merge decisions (that's Centurion, who calls Truthsayer as one tool)
- Write the rules (rule evolution goes through the Senate)
- Know about the rest of the Agora — it's a standalone tool

**Implementation:** Go binary with tree-sitter (cgo).

**Definition of done:** Truthsayer is a reliable, low-false-positive scanner that Centurion calls as part of the gate, that CI systems can run independently, and that anyone outside the Agora can use. Rule evolution has a clear process (Senate).

---

### ⚖️ Oathkeeper — The Commitment Tracker

**Why it exists:** Agents (especially Athena) say things in conversation: "I'll fix that in the next step." "We should refactor this later." "That's an existing bug." Then the session ends and it's all gone. Plans evaporate. Bugs get dismissed. Promises break silently.

**What it does:**
- Finds commitments in agent transcripts that never became work items
- Catches bugs discovered mid-work that got dismissed as "existing"
- Creates beads for forgotten promises so nothing falls through the cracks

**What it does NOT do:**
- Judge code quality (not a reviewer)
- Improve agent performance (not a learning system)
- Learn or adapt — it enforces stated intentions, period

**Implementation:** Go binary. Reads OpenClaw JSONL transcripts. Scans for commitment language patterns. Cross-references against beads.

**Definition of done:** Oathkeeper runs automatically after every session. Commitments that aren't tracked as beads get surfaced. The false positive rate is low enough that its alerts are trusted, not ignored.

---

### 🔄 Learning Loop (Ouroboros) — The Feedback Engine

**Why it exists:** Without measurement, you're guessing. Which templates work? Which models are better for which tasks? What failure patterns keep recurring? Learning Loop closes the feedback loop so the system improves over time.

**What it does:**
- Analyzes run outcomes intelligently — a Claude Code instance that understands signal, not just counts passes
- Strategizes on getting signal when data is scarce (e.g., proposes quality review beads to generate data it needs)
- Detects patterns, recommends dispatch improvements, proposes experiments
- Outputs go to Athena to discuss with Perttu — never acts unilaterally

**What it does NOT do:**
- Train model weights (we don't control the models)
- Make unilateral changes to dispatch config
- Replace mechanical checks — it layers intelligence on top

**Implementation:** Today: bash scripts + jq. Target: Claude Code instance with analysis skills, Opus judge for qualitative assessment. Four loops: per-run → hourly → daily → weekly.

**Definition of done:** Learning Loop can explain why a template is underperforming, recommend a specific change, and show evidence. Athena uses its recommendations in dispatch. Perttu trusts its analysis enough to act on it.

---

### 🏟️ Ludus Magnus — The Training Ground

**Why it exists:** You don't send a gladiator into the arena untested. Ludus Magnus is where agents prove themselves on synthetic challenges before getting real work. It answers: "can this agent actually do the thing we're about to ask it to do?"

**What it does:**
- Runs agents through structured challenges and scores them
- Compares models, prompts, and techniques on controlled tasks
- Evaluates any agent type — coding, research, analysis — before deployment

**What it does NOT do:**
- Modify agent weights (it evaluates, findings inform humans)
- Replace real-world feedback (that's Learning Loop)
- Run in production — it's the practice arena, not the game

**Implementation:** Framework exists. Needs real challenge sets and evaluation runs.

**Definition of done:** Before deploying a new model, prompt, or technique in production dispatch, it's been evaluated in Ludus Magnus. Results are comparable across runs and agents.

---

### 👁️ Argus — The Watchdog

**Why it exists:** Systems die at 3am. Processes go zombie. Disks fill up. Nobody's watching. Argus is.

**What it does:**
- Monitors infrastructure every 5 minutes and self-heals
- Kills orphan processes, restarts failed services
- Files problem beads so issues are tracked even when nobody's awake

**What it does NOT do:**
- Monitor code quality or agent output (that's Centurion)
- Depend on Relay — needs out-of-band fallback for when Relay itself is down
- Fix application bugs — it keeps the lights on, not the product correct

**Implementation:** Bash. Cron. Direct system calls — deliberately simple, no dependencies that can fail.

**Definition of done:** Argus catches and recovers from every infrastructure failure without human intervention. Problem beads exist for every incident. It survives Relay being down.

---

### 🏛️ Athena Web (The Loom Room) — The Dashboard

**Why it exists:** `bd list` in a terminal isn't enough when you have dozens of active beads across multiple repos. You need the tapestry view — everything at once, visually.

**What it does:**
- Shows all beads, status, and work history in a browser
- Gives Perttu the overview — threads, progress, blockers
- Visualizes what `bd` tracks

**What it does NOT do:**
- Replace `bd` CLI for creating/managing beads
- Do computation or decision-making
- Need to be running for the system to function (it's a view, not a dependency)

**Implementation:** Web service on port 9000.

**Definition of done:** Perttu opens a browser, sees all work across all repos, and can understand system state in under 10 seconds.

---

### 🏛️ Senate (Ecclesia) — The Deliberation Body

**Why it exists:** Some decisions need more than one perspective. A single agent has blind spots. When an issue is complex — rule changes, architecture choices, priority calls, disputed findings — the Senate provides structured multi-agent deliberation so the decision is nuanced, not reflexive.

**What it does:**
- Provides multi-perspective takes on complex issues
- Deliberates on rule changes, architecture, priorities where nuance matters
- Produces reasoned verdicts that consider tradeoffs

**What it does NOT do:**
- Catch adversarial behavior (that's Centurion's code review)
- Run constantly or govern daily operations (that's Athena)
- Replace Perttu's final say — it advises, he decides

**Implementation:** TBD. Multi-agent session (different models/configs) with structured debate protocol.

**Definition of done:** When a complex decision arises, the Senate can be convened, produce a verdict with reasoning from multiple perspectives, and the reasoning is good enough that Perttu finds it genuinely useful (not ceremony).

---

## How They Connect

```
Perttu
  │
  ▼
Athena (proactive orchestrator)
  │
  ├──[Relay]──▶ Coding Agent ──▶ work done
  │                                   │
  │              ┌────────────────────┘
  │              ▼
  ├──[Relay]──▶ Centurion (smart gate) ──uses──▶ Truthsayer
  │              │                               tests, lint, UBS
  │              ▼
  │            merge or reject (with reasoning)
  │
  ├──[Relay]──▶ Oathkeeper ──▶ scans transcripts ──▶ creates beads
  │
  ├──[Relay]──▶ Learning Loop ──▶ analysis ──▶ recommendations to Athena
  │                                              ──▶ discuss with Perttu
  │
  ├──[Relay]──▶ Ludus Magnus ──▶ evaluate agents before deployment
  │
  ├──           Argus ──▶ monitors (out-of-band, no Relay dependency)
  │
  └──[Relay]──▶ Senate ──▶ deliberates when convened ──▶ reasoned verdicts
```

## Implementation Model

Most systems are **Claude Code or Codex instances with specialized agent configs and skills**, not bash scripts. The current bash scripts are scaffolding.

| System | Today | Target |
|--------|-------|--------|
| Athena | OpenClaw main session | Same, but proactive + Relay dispatch |
| Relay | Go binary (underused) | Backbone for all agent communication |
| Centurion | Bash script (`centurion.sh`) | Claude Code instance with code review skill |
| Truthsayer | Go binary | Same (standalone tool) |
| Oathkeeper | Go binary | Same + automated via cron |
| Learning Loop | Bash + jq scripts | Claude Code instance with analysis skills |
| Ludus Magnus | Framework | Evaluation harness + challenge sets |
| Argus | Bash + cron | Same (deliberately simple) |
| Athena Web | Node.js service | Same (stabilize) |
| Senate | Concept | Multi-agent session protocol |

## Design Principles

1. **One job per system.** If you can't explain it in one sentence, split it.
2. **Communicate through Relay.** Messages, not scripts. Exception: Argus (out-of-band).
3. **Evolve independently.** Each repo ships on its own schedule. Each tool works standalone.
4. **Separation of powers.** Truthsayer enforces rules. Senate evolves rules. Centurion guards the gate. Learning Loop measures. Oathkeeper tracks commitments. No system judges its own work.
5. **Agents, not scripts.** The target is intelligent agents with skills, not bash pipelines. The bash is scaffolding.
6. **Athena is proactive.** She doesn't wait. She notices, proposes, and drives.
7. **Learning Loop advises, Perttu decides.** No system makes unilateral changes to how the factory operates.
8. **Mythology is the architecture.** The names are mental models that make the system legible. They're not decoration.
