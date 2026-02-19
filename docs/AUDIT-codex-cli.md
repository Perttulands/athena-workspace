# Audit: Codex CLI Usage in OpenClaw Workspace

**Date:** 2026-02-16  
**Auditor:** Subagent (Claude Opus)  
**Scope:** All docs, scripts, and config mentioning Codex CLI  
**Installed version:** codex-cli 0.99.0

---

## 1. What Codex CLI Actually Is (from official docs + installed binary)

### Identity
Codex CLI is OpenAI's local coding agent. The current version is a **Rust** implementation (the legacy TypeScript version is superseded). It runs locally in your terminal with full access to your filesystem and shell.

### Two Execution Modes
- **Interactive:** `codex` or `codex "prompt"` — full-screen TUI
- **Non-interactive:** `codex exec "prompt"` — headless, for scripts/CI. Reads stdin with `-` arg.

### Sandbox Modes (`-s, --sandbox`)
| Mode | Effect |
|------|--------|
| `read-only` | Read-only access |
| `workspace-write` | Write within workspace only (default) |
| `danger-full-access` | Full disk and network access |

### Approval Policies (`-a, --ask-for-approval`)
| Policy | Effect |
|--------|--------|
| `untrusted` | Only run trusted commands without asking |
| `on-failure` | Run all, ask on failure |
| `on-request` | Model decides when to ask |
| `never` | Never ask |

### Convenience Flags
| Flag | Equivalent | Effect |
|------|-----------|--------|
| `--full-auto` | `-a on-request -s workspace-write` | Sandboxed, no network, model asks when needed |
| `--yolo` | `--dangerously-bypass-approvals-and-sandbox` | **No sandbox, no approvals.** Full access. |

**Key insight:** `--yolo` is a hidden alias (not shown in `codex --help`) but is documented on the official site and works on v0.99.0. It is the official shorthand for `--dangerously-bypass-approvals-and-sandbox`.

### Our Usage
We run: `codex exec --yolo "prompt"` (after this audit). This gives full unrestricted shell access — identical capabilities to `claude --dangerously-skip-permissions`.

### Default Model
The CLI default is `o4-mini`. We override to `gpt-5.3-codex` which is the recommended model for coding tasks (confirmed in official docs).

---

## 2. Files Audited and Fixed

### Fixed: `scripts/lib/config.sh`
- **Was:** `-s danger-full-access` (sandbox mode flag only)
- **Now:** `--yolo` (full bypass — sandbox AND approvals)
- **Why:** `-s danger-full-access` sets sandbox mode but doesn't explicitly bypass the approval policy. `--yolo` is cleaner, more explicit, and matches Perttu's directive.

### Fixed: `scripts/ralph.sh`
- **Was:** `codex exec -s danger-full-access "$prompt"` and `codex exec -s danger-full-access -c ...`
- **Now:** `codex exec --yolo "$prompt"` and `codex exec --yolo -c ...`
- **Why:** Same as above.

### Fixed: `config/agents.json`
- **Was:** `"flags": ["exec", "-s", "danger-full-access"]`
- **Now:** `"flags": ["exec", "--yolo"]`
- **Was:** Warning: `"full-auto and dangerously-bypass-approvals-and-sandbox are mutually exclusive"`
- **Now:** Warning: `"We use --yolo (alias for --dangerously-bypass-approvals-and-sandbox). Never use --full-auto (sandboxed, no network)."`
- **Why:** Align config with actual usage and make the intent clear.

### Fixed: `state/CLI-COMPAT.md`
- **Was:** Claims we use `--dangerously-bypass-approvals-and-sandbox`
- **Now:** Says we use `--yolo` (with alias noted)
- **Why:** We use the short alias. The long form is just the canonical name.

### Fixed: `docs/REVIEW-agent-comms.md`
- **Was:** Section 2.1 claimed "Codex runs in a sandbox and communicates via stdin/stdout. It doesn't have arbitrary shell access like Claude Code does." This was **completely wrong**.
- **Now:** Section 2.1 correctly states Codex runs with `--yolo` (full access, no sandbox). Same capabilities as Claude Code. The original recommendation for a "Codex compatibility section" in the PRD was invalid.
- **Also:** Summary item #3 struck through as INVALID.
- **Why:** This was the single most dangerous misunderstanding — it could cause future architecture decisions to needlessly limit Codex's role.

### NOT Fixed (correct as-is)

| File | Status | Notes |
|------|--------|-------|
| `TOOLS.md` | ✅ Correct | Lists `codex` with `gpt-5.3-codex`, accurate |
| `AGENTS.md` | ✅ Correct | Dispatch examples use `codex` agent type |
| `MEMORY.md` | ✅ Correct | Says `codex exec`, accurate model |
| `skills/coding-agents/SKILL.md` | ✅ Correct | Accurate description of codex role |
| `scripts/dispatch.sh` | ✅ Correct | Uses `build_agent_cmd` from config.sh (now fixed) |
| `scripts/agent-preflight.sh` | ✅ Correct | Checks CLI capability, doesn't hardcode flags |
| `scripts/cli-compat-test.sh` | ✅ Correct | Tests for `--full-auto` and `--dangerously-bypass-approvals-and-sandbox` as capability checks |
| `scripts/refine.sh` | ✅ Correct | Delegates to dispatch.sh |
| `scripts/project-init.sh` | ✅ Correct | Creates `.codex/config.toml` with right model |
| `memory/archive.md` | ✅ Historical | Notes about flag incompatibility are accurate history |
| `memory/2026-02-12.md` | ✅ Historical | Same |
| `memory/2026-02-16.md` | ✅ Correct | Already says `--yolo` |

---

## 3. Patterns of Misunderstanding

### Pattern A: Confusing flag names with capability restrictions
The long flag name `--dangerously-bypass-approvals-and-sandbox` implies there IS a sandbox being bypassed. An Opus agent read this name and concluded Codex is inherently sandboxed. In reality, with `--yolo`, Codex has zero restrictions. The flag name describes what it bypasses in the default config, not a hard architectural limit.

### Pattern B: Three different flag references for the same intent
Our codebase had three different representations of "give Codex full access":
1. `-s danger-full-access` (in scripts — technically sandbox-only, not approval bypass)
2. `--dangerously-bypass-approvals-and-sandbox` (in CLI-COMPAT.md)
3. `--yolo` (in today's memory)

This inconsistency is how misconceptions spread. Now standardized to `--yolo` everywhere.

### Pattern C: Sandbox vs. approval confusion
Codex has two independent security axes: sandbox mode (what it CAN do) and approval policy (when it must ASK). `-s danger-full-access` only sets the sandbox axis. `--yolo` sets both. In non-interactive exec mode the difference is subtle (approval prompts can't happen anyway), but using `--yolo` is semantically correct and explicit.

---

## 4. Recommendations

1. **Always use `--yolo` for Codex dispatch.** Never `-s danger-full-access`, never `--full-auto`, never the long form. One flag, one name, no confusion.

2. **Treat Codex and Claude as capability-identical.** Both have full shell access. Never architect around assumed Codex limitations.

3. **When documenting flags, use what we actually invoke.** Don't reference the long canonical names in operational docs. Reserve those for reference/compatibility docs.

4. **Add `--yolo` to preflight checks.** Currently `agent-preflight.sh` checks for `--full-auto` but not `--yolo`. Since `--yolo` is a hidden alias not shown in `--help`, a runtime check (`codex exec --yolo --help` exits 0) would be better than a help-text grep.

5. **Pin the Codex CLI version.** We're on v0.99.0. The `--yolo` alias exists but is undocumented in `--help`. Future versions may change behavior. Pin version in deployment scripts.
