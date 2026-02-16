---
name: beads
description: Track work with beads. Use for creating, listing, closing, searching, and managing work items and dependencies.
---

# Beads (`br`)

Agent-first work tracker. Every piece of work gets a bead.

## Core Commands

```bash
br create --title "What needs doing" --priority 1   # Create (prints bead ID)
br q "Quick capture"                                  # Quick create, ID only
br list                                               # List open beads
br show <id>                                          # Details
br close <id>                                         # Done
br ready                                              # Unblocked, not deferred
br search "query"                                     # Search
br label add <id> <label>                             # Tag it
br dep add <id> --blocks <other-id>                   # Dependencies
br stats                                              # Project stats
br stale                                              # Find stale beads
br defer <id>                                         # Schedule for later
```

## Role in the System

- Unit of dispatch — every `dispatch.sh` call takes a bead ID
- Agents reference their bead throughout work
- Results land in `state/results/<bead>.json`
- Verify results in `state/results/<bead>-verify.json`
- Oathkeeper and Argus auto-create beads for detected problems
