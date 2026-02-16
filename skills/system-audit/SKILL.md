---
name: system-audit
description: Full system audit — review all repos, scripts, infrastructure, and orchestration state. Use when things are broken, after incidents, before major changes, or when you need ground truth about the system. Covers git state, script correctness, state file hygiene, and architecture review.
---

# System Audit

Stop-the-world diagnostic. Deploy when the foundation is suspect.

## When to Use

- After failed dispatches or lost agent work
- Before refactoring infrastructure scripts
- Periodic health check (weekly or after incidents)

## Process

1. Create two beads (scripts review + repo audit)
2. Dispatch opus agent for **scripts review**: dispatch.sh, centurion.sh, verify.sh, lib/*.sh, config/agents.json. Output: `state/reviews/<bead>-system-review.md`
3. Dispatch opus agent for **repo audit**: scan all `/home/perttu/` git repos. Per repo: branch, dirty state, stashes, worktrees, unmerged branches, sync status. Also check state files for stale/stuck records.
4. Review both reports, create beads for findings, fix in priority order: data loss → silent failures → state hygiene → design improvements
5. Update MEMORY.md and relevant docs

**Principle:** Never fix anything until you have ground truth.
