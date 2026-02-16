# Harness Engineering — Key Patterns (OpenAI, Feb 2026)

Source: https://openai.com/index/harness-engineering/

## Core Philosophy
- 0 lines of manually-written code. Humans steer, agents execute.
- 1M lines of code, ~1500 PRs, 3 engineers → 3.5 PRs/engineer/day
- Built in ~1/10th the time of manual coding

## Patterns Worth Stealing

### 1. AGENTS.md as Table of Contents, Not Encyclopedia
- ~100 lines. Pointers to deeper docs, not the docs themselves.
- Progressive disclosure: agents start with small stable entry point, taught where to look next.
- Knowledge base in structured docs/ directory as system of record.

### 2. Repository Knowledge IS the System of Record
- If it's not in the repo, it doesn't exist to the agent.
- Slack discussions, Google Docs, people's heads = illegible. Push into repo.
- Design docs catalogued with verification status.
- Plans as first-class artifacts — versioned, co-located.

### 3. Agent Legibility > Human Legibility
- Optimize for agent's ability to reason about the codebase.
- Favor "boring" technologies — composable, stable APIs, well-represented in training data.
- Sometimes cheaper to reimplement than work around opaque libraries.

### 4. Enforce Architecture Mechanically
- Rigid layer model with dependency direction validation (custom linters).
- Invariants, not micromanagement. "Parse at boundary" but don't prescribe how.
- Taste encoded into tooling: naming conventions, file size limits, structured logging.
- Custom lint error messages = remediation instructions injected into agent context.

### 5. Make the App Legible to Agents
- Bootable per git worktree — one instance per change.
- Chrome DevTools Protocol for DOM snapshots, screenshots, navigation.
- Local observability stack (LogQL, PromQL) per worktree, torn down after task.
- Agents can validate performance, reproduce bugs, reason about UI.

### 6. Ralph Loop for PR Completion
- Agent writes code → reviews own changes → requests agent reviews → iterates until all reviewers satisfied.
- Humans may review but aren't required to. Push review toward agent-to-agent.

### 7. Throughput Changes Merge Philosophy
- Minimal blocking merge gates. Short-lived PRs.
- Corrections are cheap, waiting is expensive.
- Test flakes → follow-up runs, not blocking.

### 8. Doc Gardening Agent
- Recurring agent scans for stale/obsolete docs that don't reflect real code.
- Opens fix-up PRs automatically.

### 9. Single Codex Runs Working 6+ Hours
- While humans sleep. This is the model we're building toward.

## What This Means For Us
- Our AGENTS.md is already a map. Good.
- We need: structured docs/ directory, mechanical enforcement, agent-legible app state.
- Our flywheel analysis → their doc gardening. Same pattern, different domain.
- Their linters with agent-friendly error messages = our verify.sh evolved.
- Git worktrees per agent = we should adopt this for parallel work.

## RTK - Rust Token Killer
- Installed: v0.14.0 at ~/.local/bin/rtk
- Hook: ~/.claude/hooks/rtk-rewrite.sh (auto-rewrites CLI commands for token savings)
- Settings: ~/.claude/settings.json (PreToolUse hook configured)
- 60-90% token reduction on ls, cat, grep, git, npm test, docker
- All new Claude Code agents benefit automatically via the hook
- Check savings: rtk gain
