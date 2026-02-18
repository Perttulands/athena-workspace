---
name: beads
description: Track work with beads. Use for creating, listing, closing, searching, and managing work items and dependencies.
---

# Beads (`bd`)

Agent-first work tracker. Every piece of work gets a bead.

## Core Commands

```bash
bd create --title "What needs doing" --priority 1   # Create (prints bead ID)
bd q "Quick capture"                                 # Quick create, ID only
bd list                                               # List open beads
bd show <id>                                          # Details
bd close <id>                                         # Done
bd ready                                              # Unblocked, not deferred
bd search "query"                                     # Search
bd label add <id> <label>                             # Tag it
bd dep add <id> --blocks <other-id>                   # Dependencies
bd stats                                              # Project stats
bd stale                                              # Find stale beads
bd defer <id>                                         # Schedule for later
```

## Role in the System

- Unit of dispatch — every `dispatch.sh` call takes a bead ID
- Agents reference their bead throughout work
- Results land in `state/results/<bead>.json`
- Verify results in `state/results/<bead>-verify.json`
- Oathkeeper and Argus auto-create beads for detected problems
