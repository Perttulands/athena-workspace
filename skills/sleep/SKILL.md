---
name: sleep
description: Graceful context shutdown. Use before /new, /reset, or when context is degraded. Updates docs, memory, changelogs, and produces a handoff message for the next session.
---

# Sleep — Graceful Context Handoff

Run this before ending a session. Produces a clean handoff so the next session starts sharp.

## Process

### 1. Memory Flush
- Write today's work to `memory/YYYY-MM-DD.md` (create or append)
- Update `MEMORY.md` if any core truths, active projects, or system facts changed
- Move anything resolved/historical to `memory/archive.md`

### 2. Doc Sweep
- Check if any workspace docs (`AGENTS.md`, `TOOLS.md`, `SOUL.md`, `USER.md`) need updates based on what happened this session
- Update stale content. Docs describe what IS.

### 3. Changelog
- If scripts, skills, or infrastructure changed: append to `CHANGELOG.md`

### 4. Handoff Message
Send Perttu a copyable message in this format:

```
🦉 Session handoff — YYYY-MM-DD

## What happened
- [bullet points of work done]

## State changes
- [files created/modified/deleted]
- [beads opened/closed]
- [anything the next session should know]

## Open threads
- [anything unfinished or pending]
```

Keep it short. The next session has memory files — this is just a quick-start summary to paste in.

### 5. Confirm Ready
Tell Perttu the handoff is ready and they can `/new`.
