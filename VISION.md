# VISION.md — Why We Build

## The Dream

You go to sleep. You wake up and the work is done. Not just "agents ran" — the work is **done**. Verified, committed, tested. Decisions were made in your absence and they were good decisions because the system knows your standards, your codebase, your taste.

Where it hit ambiguity, it didn't guess — it flagged it cleanly for your morning review. Where an agent failed, it diagnosed why, adjusted the approach, and retried with a different model or rewritten prompt. Where it spotted a dependency you didn't mention, it handled it.

And while doing all that, it got smarter. It analyzed tonight's runs against last week's runs and updated the templates. The agents tomorrow are better than the agents today, not because you tuned anything, but because the system tuned itself.

That's not a state machine. That's a **second brain with agency**. One that shares your judgment because it's been learning from your decisions since day one.

## The Problem

One person. Unlimited ideas. 24 hours. Traditional leverage — hiring, outsourcing — is slow, expensive, and adds communication overhead. A single AI agent is linear. One task, one result, one wait.

## The Solution

A personal AI factory that compounds. Perttu provides vision, strategy, and taste. The system builds.

```
Perttu thinks → Athena decomposes → Agents execute in parallel → Verify → Learn → Repeat faster
```

The value isn't any single agent run. It's the compounding loop:
- Better prompts from analyzing what worked
- Better verification from patterns in failures
- Better decomposition from understanding task complexity
- Better agent selection from performance data across models

## The Hard Problems

These are what separate a cron-job-and-scripts setup from a genuine second brain:

1. **Judgment without the human.** Can the system evaluate quality — not just "did tests pass" but "is this good work"? This requires calibration data: examples of what Perttu accepted vs. rejected, and why. The system must learn taste.

2. **Planning, not just execution.** Moving from "here's a task list, go" to "here's a goal, figure out the tasks." Requires a rich backlog with strategic context, dependency awareness, and the ability to sequence work intelligently.

3. **Self-improvement that's automatic.** The flywheel analysis can't just produce reports. It must feed back into templates, prompt selection, and model routing without human intervention. The system tunes itself.

4. **Autonomous strategic operation.** The overnight session isn't executing a pre-baked plan. It's reading state, assessing the situation, making real judgment calls, and adapting when things go sideways. Every fresh session wakes up cold and runs the show because the state layer carries full situational awareness.

## The Endgame

Perttu is the bottleneck only at the level of strategy and taste — which is exactly where a human should be. Everything below that level scales horizontally through agents that get better every day.

## The Principles

1. **Structure over discipline.** Correct behavior is encoded in tooling, not remembered by agents. Mechanical enforcement with custom linters and agent-friendly error messages — not prose rules that get ignored.

2. **Single source of truth.** Every fact lives in exactly one place. Models, flags, config — one file that all scripts read. If it's not in the repo, it doesn't exist to agents. If it exists in two places, one of them is wrong. Duplication is how silent defaults happen.

3. **Agent legibility is the optimization target.** Not human convenience. Optimize for the agent's ability to reason about the codebase. This sometimes means boring technologies with stable APIs and rich training corpus over clever abstractions.

4. **AGENTS.md is a table of contents, not an encyclopedia.** Keep it lean — a map showing agents where to look next, not the knowledge itself. Progressive disclosure from a stable, small entry point.

5. **Data drives improvement.** Every run produces a structured record. Analysis surfaces what to improve. The flywheel is mechanical, not aspirational.

6. **Compound, don't repeat.** Templates, schemas, and analysis scripts ensure nothing is done from scratch twice.

7. **Enforce architecture mechanically.** Encode invariants in linters with remediation instructions. Let agents understand boundaries through tooling, not documentation that drifts.

8. **Doc gardening is automated hygiene.** Docs describe what IS, never what WAS. Recurring analysis detects drift between code and documentation, opening fix-up PRs automatically.

9. **Git worktrees enable agent isolation.** Parallel work requires parallel environments. Each agent gets its own worktree — bootable, testable, disposable.

10. **Always available.** The coordinator never blocks on agents. Async dispatch, callback-driven results.

11. **Foundations first.** Build the full loop before optimizing any part of it. A half-built factory produces nothing.

12. **Judgment is earned.** Autonomous operation grows from calibration data and proven track record, not from day one assumptions.
