# The Event Loop for Intelligence: Multi-Agent Architectures with Persistent Autonomous Bots

**February 2026**

---

## Abstract

Large language model agents have rapidly evolved from single-turn completion engines to interactive coding assistants capable of autonomous file editing, shell execution, and web browsing. Yet the dominant deployment pattern remains the **process model**: a human invokes an agent, the agent executes, and the agent exits. This paper argues that the critical next step is not better models but better **architecture** — specifically, the transition from process-model agents to **daemon-model agents**: persistent event loops that multiplex heterogeneous inputs into a single cognitive context and route outputs across multiple surfaces. We analyze the OpenClaw gateway as a concrete implementation of this pattern, examine multi-agent topologies it enables (hub, mesh, hierarchical), discuss economic implications of heterogeneous model allocation, and identify limitations and open problems. Our central claim is that the compound value of N persistent, specialized, coordinating agents is qualitatively different from N isolated agent invocations — not because any single capability is unreproducible, but because the daemon architecture makes the *default* behavior autonomous, stateful, and reachable, rather than requiring explicit orchestration scaffolding for each of these properties.

---

## 1. Introduction

Consider two ways to use an LLM agent to monitor a production server:

**Approach A (Process model):** Write a cron job that invokes a CLI agent every 30 minutes, pipes in log output, and writes the agent's response to a file. If you want to ask the agent about an anomaly it found, open a terminal and start a new session. The agent has no memory of what it found earlier unless you engineer a context-injection pipeline. If you want results on your phone, build a notification script.

**Approach B (Daemon model):** A persistent bot wakes on a 30-minute heartbeat, checks logs, writes findings to its own memory, and messages you on Telegram. You reply from your phone: "Expand on that CPU spike." The bot has full context — it found the spike ten minutes ago in the same cognitive session. It can also receive an urgent webhook from your CI system mid-conversation, triage it, and notify a separate specialist bot via inter-agent mail.

Every individual capability in Approach B can be replicated in Approach A with enough shell scripts, state files, and queue systems. The thesis of this paper is that this misses the point. The value is architectural: when persistence, multiplexed I/O, identity, and reachability are **first-class primitives** rather than bolted-on afterthoughts, qualitatively different systems become the natural default rather than heroic engineering projects.

---

## 2. Background

### 2.1 The Rise of CLI Coding Agents

2024–2025 saw the emergence of powerful CLI-based coding agents: Anthropic's Claude Code, OpenAI's Codex CLI, Cursor, Aider, and others. These tools give an LLM access to a shell, file system, and browser, enabling autonomous multi-step software engineering tasks. Their interaction model is fundamentally **synchronous and ephemeral**:

```
human invokes agent → agent runs → agent exits
```

Session state exists only for the duration of the invocation. Some tools persist conversation history to disk, but each new invocation re-ingests context from scratch. There is no background execution, no event-driven wake, no multiplexed input.

### 2.2 Orchestration Frameworks

Frameworks like LangGraph, CrewAI, and AutoGen address multi-agent coordination but operate within a single process boundary. They compose agents as function calls within a Python runtime — powerful for workflow automation, but still bound to the process lifecycle. When the orchestrator exits, the agents cease to exist.

### 2.3 The Daemon Gap

Operating systems solved an analogous problem decades ago. Early programs were batch jobs: load, execute, exit. The introduction of **daemons** — long-running processes that listen for events and respond — enabled servers, databases, and the entire client-server paradigm. The agent ecosystem in 2025 is largely still in the batch-job era.

---

## 3. Core Architecture: The Agent as Daemon

### 3.1 Process vs. Daemon

The distinction maps cleanly from systems programming:

| Property | Process (CLI Agent) | Daemon (OpenClaw Bot) |
|---|---|---|
| Lifecycle | Invoke → execute → exit | Start → listen → respond → persist |
| State | Per-invocation (or manual reload) | Continuous across events |
| Input | stdin / arguments | Multiplexed: cron, messaging, webhooks, agent mail, heartbeats |
| Output | stdout / files | Multi-surface: messaging, files, browser, devices |
| Reachability | Requires terminal access | Any connected surface (phone, desktop, API) |
| Initiative | None (human-triggered only) | Self-initiating via timers and events |
| Identity | Anonymous or per-config | Persistent: SOUL.md, memory/, accumulated knowledge |

One can approximate daemon behavior by wrapping a CLI agent in cron, a message queue consumer, and a state management layer. But this is the "Turing tarpit" argument — technically possible, practically a different system. The engineering cost of maintaining those wrappers, ensuring state consistency, handling concurrent inputs, and managing identity across invocations is substantial and error-prone.

### 3.2 The Event Loop

OpenClaw implements the daemon model as a **cognitive event loop**:

```
┌─────────────────────────────────────────────────┐
│                  INPUT SOURCES                   │
│                                                  │
│  ┌──────┐ ┌─────────┐ ┌────────┐ ┌───────────┐ │
│  │ Cron │ │Telegram │ │Webhook │ │Agent Mail │ │
│  └──┬───┘ └────┬────┘ └───┬────┘ └─────┬─────┘ │
│     │          │          │             │        │
│     └──────────┴─────┬────┴─────────────┘        │
│                      ▼                           │
│  ┌───────────────────────────────────────────┐   │
│  │         PERSISTENT AGENT CONTEXT          │   │
│  │                                           │   │
│  │  SOUL.md ─ identity & directives          │   │
│  │  MEMORY.md ─ accumulated knowledge        │   │
│  │  memory/YYYY-MM-DD.md ─ daily journal     │   │
│  │  Model (configurable per bot)             │   │
│  │  Tools (shell, browser, MCP, devices)     │   │
│  └───────────────────┬───────────────────────┘   │
│                      ▼                           │
│  ┌──────┐ ┌─────────┐ ┌────────┐ ┌───────────┐ │
│  │Files │ │Telegram │ │Browser │ │  Nodes    │ │
│  └──────┘ └─────────┘ └────────┘ └───────────┘ │
│                                                  │
│                 OUTPUT SURFACES                   │
└─────────────────────────────────────────────────┘
```

The critical insight is that all input sources converge on **one cognitive context**. A cron-triggered health check and a user's Telegram question occupy the same "mind." The agent can reference what it found autonomously when answering a human question, without any explicit context-passing machinery. This is not a technical impossibility for process-model agents — it is an architectural default that changes what builders naturally create.

### 3.3 Identity and Memory as First-Class Primitives

Each OpenClaw bot boots with a defined identity:

- **SOUL.md**: Personality, directives, role definition, operating principles
- **MEMORY.md**: Accumulated high-level knowledge and lessons learned
- **memory/YYYY-MM-DD.md**: Daily journal entries, auto-pruned over time
- **Project context files**: AGENTS.md, TOOLS.md, USER.md — the bot's "onboarding packet"

This is not prompt engineering. It is closer to an operating system's init sequence: the bot loads its identity from disk on every session start, ensuring continuity across model context window boundaries. Memory files are written *by the bot itself* during operation, creating a self-reinforcing loop: experience → written memory → future context → better decisions.

---

## 4. Multi-Agent Patterns

The daemon model's real power emerges when multiple bots operate as a system. We identify three primary topologies:

### 4.1 Hub Model

```
                    ┌─────────┐
          ┌────────►│ Builder │
          │         └─────────┘
┌─────────┴──┐      ┌─────────┐
│ Coordinator ├─────►│ Monitor │
└─────────┬──┘      └─────────┘
          │         ┌─────────┐
          └────────►│Reviewer │
                    └─────────┘
```

A single coordinator bot receives all human input and routes tasks to specialist bots. The coordinator maintains the master plan; specialists execute. Communication flows through the hub via MCP Agent Mail or direct messaging.

**Advantages:** Clear authority, simple mental model, single point of contact for the human.
**Disadvantages:** Bottleneck at coordinator, single point of failure, coordinator context window consumed by routing overhead.

### 4.2 Mesh Model

```
  ┌─────────┐     ┌─────────┐
  │ Bot A   │◄───►│ Bot B   │
  └────┬────┘     └────┬────┘
       │               │
       │  ┌─────────┐  │
       └─►│ Bot C   │◄─┘
          └─────────┘
```

All bots can communicate with all other bots via Agent Mail. Each bot acts autonomously within its domain and reaches out to peers when it encounters cross-domain issues.

**Advantages:** No single bottleneck, resilient, scales naturally.
**Disadvantages:** Coordination complexity grows quadratically, potential for circular dependencies or conflicting actions, harder for humans to audit.

### 4.3 Hierarchical Model

```
  ┌──────────────────┐
  │  Athena (Strategy)│
  └────────┬─────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
┌────────┐  ┌──────────┐
│Hephaest│  │  Argus   │
│(Build) │  │(Monitor) │
└───┬────┘  └──────────┘
    │
    ▼ (spawns disposable)
┌──────────┐
│Claude Code│  ← process-model agent
│  worker   │     (ephemeral)
└──────────┘
```

This is the most natural pattern for real-world deployment. A strategic bot (Athena) coordinates persistent specialist bots, which in turn spawn **ephemeral CLI agents** as disposable workers for bounded tasks. This hybrid model uses each architecture where it is strongest:

- **Daemons** for persistent roles requiring state, identity, and reachability
- **Processes** for bounded, parallelizable execution tasks (run tests, refactor a file, generate a report)

The Athena system demonstrates this in practice: a strategic coordinator bot maintains project state, dispatches coding tasks to Claude Code instances running in tmux sessions, tracks progress via a bead-based issue system, and reports results to the human via Telegram. The CLI agents are deliberately disposable — their output matters, their continued existence does not.

---

## 5. Economic Model

A frequently overlooked advantage of multi-bot architectures is **heterogeneous model allocation**. Not all cognitive tasks require frontier-model intelligence:

| Task | Model Tier | Approx. Cost Ratio |
|---|---|---|
| Overnight log monitoring | Sonnet / Haiku | 1x |
| Code review, routine builds | Sonnet | 3x |
| Architecture decisions, planning | Opus | 15x |
| Quick status checks, formatting | Haiku | 0.3x |

In a single-agent system, the human's primary assistant runs on the most capable (expensive) model because it must handle the hardest tasks. In a multi-bot system, only the strategy bot needs a frontier model. Monitoring, building, formatting, and triage bots can run on cheaper models without degrading the system's peak capability.

The economic structure mirrors human organizations: you don't pay executive salaries for data entry. The daemon architecture makes this natural — each bot has its own model configuration in its OpenClaw config, and switching a monitoring bot from Opus to Sonnet is a one-line change, not a system redesign.

**Rough estimates for a three-bot system (daily operation):**

- Single Opus agent handling everything: ~$15–30/day at moderate usage
- Athena (Opus, strategy only): ~$5–10/day
- Builder (Sonnet, coding tasks): ~$3–5/day
- Monitor (Haiku, periodic checks): ~$0.50–1/day
- **Total: ~$8.50–16/day for greater capability coverage**

These numbers are illustrative and will compress as model costs continue their rapid decline, but the *principle* of heterogeneous allocation remains valuable at any price point.

---

## 6. Limitations and Honest Assessment

### 6.1 What the Daemon Model Does NOT Solve

**Context window limits.** A daemon bot still has a finite context window. Long-running sessions eventually hit the boundary and must restart, losing in-context state. Memory files mitigate this but are a lossy compression of lived experience. This is the most fundamental limitation.

**Reliability.** LLMs are stochastic. A daemon bot that acts autonomously can make mistakes at 3 AM with no human in the loop. Guardrails, confirmation requirements for destructive actions, and human-in-the-loop patterns remain essential. Autonomy without reliability guarantees is a liability.

**Complexity overhead.** A single CLI agent is simple: one process, one human, one task. Multi-bot architectures introduce coordination overhead, debugging complexity, and failure modes that do not exist in simpler setups. For many use cases, a CLI agent in a terminal is the right answer.

**Reproducibility.** Each individual capability (cron scheduling, messaging integration, persistent state, multi-agent coordination) *can* be built around CLI agents with sufficient scripting. The daemon architecture's value is in making these the default, not in enabling the impossible. This is a legitimate critique: the pattern's value is proportional to the complexity of what you're building.

### 6.2 When NOT to Use This Pattern

- **One-off tasks.** If you need to refactor a single file, spawn a CLI agent. The daemon model adds zero value for bounded, non-recurring work.
- **Single-user, single-task workflows.** If your entire interaction with AI is "ask question, get answer," a chatbot is the right tool.
- **Cost-sensitive environments.** Persistent bots with heartbeats consume tokens even when idle. If every dollar matters, pay-per-invocation process-model agents are more economical for light workloads.

---

## 7. Future Work

### 7.1 Formal Coordination Protocols

Current inter-bot communication via Agent Mail is unstructured natural language. Future work should explore typed message schemas, capability negotiation, and formal task delegation protocols — analogous to the evolution from ad-hoc TCP to HTTP to gRPC in networked systems.

### 7.2 Adaptive Model Selection

Bots could dynamically select their own model based on task complexity rather than using a static configuration. A monitoring bot might escalate to Opus when it detects an anomaly that exceeds its current model's analytical capacity, then drop back to Haiku for routine checks.

### 7.3 State Synchronization

Multi-bot systems need shared state primitives beyond file-system-level coordination. Distributed agent state — analogous to distributed databases — is an open research problem. Current approaches (shared file system, Agent Mail) work but do not scale gracefully.

### 7.4 Verification and Trust

As bot autonomy increases, verification becomes critical. How does a coordinator bot verify that a specialist bot completed a task correctly? Current approaches rely on output inspection (the coordinator reads the specialist's work), but formal verification of LLM-generated work remains unsolved.

---

## 8. Conclusion

The transition from process-model to daemon-model agents recapitulates a pattern seen repeatedly in computing history: batch processing to interactive systems, CGI scripts to application servers, serverless functions to persistent services. Each transition trades simplicity for capability, and each is justified only when the problem demands it.

For AI agents, the daemon model is justified when:
1. The agent must be **reachable** without terminal access
2. The agent must **act on its own schedule**, not only in response to human triggers
3. The agent must maintain **persistent state** across interactions
4. Multiple agents must **coordinate** as a system
5. The human wants to be a **director**, not an operator

The OpenClaw architecture demonstrates that these properties emerge naturally from a straightforward design: an event loop that multiplexes inputs into a persistent cognitive context with file-backed identity and memory. The resulting system — persistent, autonomous, reachable, stateful — is not a marginal improvement over CLI agents. It is a different architectural category, enabling multi-agent organizations that operate continuously at machine speed while the human retains strategic control.

The event loop is not a new idea. Applying it to intelligence is.

---

## References

1. Anthropic. "Claude Code: An agentic coding tool." 2025.
2. OpenAI. "Codex CLI." 2025.
3. LangChain. "LangGraph: Multi-agent orchestration." 2024.
4. Stevens, W.R. "Advanced Programming in the UNIX Environment." Addison-Wesley, 1992. (Process vs. daemon distinction)
5. OpenClaw. Gateway documentation and architecture. 2025–2026.

---

*Corresponding system: OpenClaw v2.x running on Ubuntu 24.04, Hetzner Cloud (Helsinki). Case study based on the Athena multi-agent deployment, February 2026.*
