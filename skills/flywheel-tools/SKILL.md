---
name: flywheel-tools
description: Agentic coding flywheel tools for work tracking, session search, bug scanning, and repo operations.
---

# Flywheel Tools

## CASS — Agent Session Search

```bash
cass search "authentication fix"              # Full-text search
cass search --semantic "how to fix auth"      # Semantic search
cass index --full                             # Full reindex
cass stats                                    # Index stats
cass status                                   # Health check
```

## BV — Beads TUI Viewer

```bash
bv                          # Launch TUI
bv --project /path/to/repo  # Specific project
bv --check-drift             # Check drift from baseline
bv --agent-brief <dir>       # Export agent brief bundle
```

## NTM — Named Tmux Manager

```bash
ntm spawn myproject --cc=2 --cod=2    # 2 Claude + 2 Codex agents
ntm attach myproject                   # Attach
ntm send myproject --all "fix bugs"   # Broadcast to all
ntm list                               # List sessions
ntm palette                            # TUI command palette
```

## Coordination Notes

The workspace no longer uses MCP Agent Mail. Agent coordination relies on dispatch context,
shared-branch discipline, and wake callbacks.

## RTK — Token Reduction Proxy

```bash
rtk ls <dir>       # Token-optimized ls
rtk tree <dir>     # Token-optimized tree
rtk read <file>    # Filtered file read
rtk git log        # Compact git output
```

60-90% token savings. Auto-active via Claude Code hook.

## DCG — Destructive Command Guard

Claude Code safety hook. Auto-blocks dangerous commands (rm -rf, etc). Runs as PreToolUse hook.
