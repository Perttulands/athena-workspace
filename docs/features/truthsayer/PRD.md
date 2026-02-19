# Truthsayer — PRD

_Last updated: 2026-02-19_

## Purpose

Truthsayer is the **law enforcer** of the Agora. He scans code for anti-patterns across 5 languages using 88 rules, and reports violations. He does not write the laws — that's the Senate's job. He does not guard the gate — that's Centurion's job. He enforces what's written.

**One sentence:** Static analysis scanner that catches bugs linters miss.

## Current State

**Working:**
- 88 detection rules across Go, JavaScript/TypeScript, Python, Bash, config files
- AST-level analysis via tree-sitter (JS/TS/Python) and go/ast (Go)
- CLI: `scan`, `check`, `watch`, `rules`, `doctor`
- Pre-commit hook installation
- JSON and terminal output formats
- CI integration (GitHub Actions)
- Configuration via `.truthsayer.toml`

**Location:** `/home/chrote/athena/tools/truthsayer`

**Repo:** `github.com/Perttulands/truthsayer`

## What Truthsayer Does

1. **Scans code** for anti-patterns (silent errors, missing timeouts, mock leakage, etc.)
2. **Reports findings** with file, line, snippet, severity, and fix suggestion
3. **Blocks commits** via pre-commit hook when errors are found
4. **Integrates with CI** to fail builds on violations

## What Truthsayer Does NOT Do

1. **Write laws** — Rule evolution goes through the Senate
2. **Guard the gate** — Centurion calls Truthsayer as one input among many
3. **Learn from runs** — That's Learning Loop's job
4. **Make judgment calls** — The judgment system (below) adds nuance, but rules are deterministic

## Target State

### The Judgment System

The current scanner is binary: violation or not. Real code has context. The target state adds **judgment**:

```
scan → findings → judge (LLM) → verdicts (guilty/not-guilty/advisory)
                      ↑
                precedents.json
```

**Key features:**
1. **Precedents accumulate** — When judge rules "not-guilty" on a pattern, that precedent is stored
2. **High-confidence precedents skip LLM** — Cost control, <$0.01/commit after warmup
3. **Law updates bubble up** — Consistent rulings propose rule amendments to Senate
4. **Three verdicts:** guilty (block), not-guilty (pass + precedent), advisory (pass + track)

**Design doc:** `JUDGMENT.md` in truthsayer repo

### Senate Integration

When Truthsayer sees a pattern that consistently gets ruled one way:
1. Truthsayer proposes a law update
2. Senate deliberates
3. Verdict: amend rule, add exception, or keep as-is
4. Truthsayer implements the amendment

**Current example:** Senate verdict `quick-1771535739` ruled to amend `silent-fallback` for trap contexts.

## Definition of Done

Truthsayer is "done" when:

1. ✅ Core scanner works (88 rules, 5 languages)
2. ✅ Pre-commit hooks work
3. ✅ CI integration works
4. ⬜ `truthsayer judge` command implemented
5. ⬜ Precedent system stores and retrieves judgments
6. ⬜ High-confidence precedents auto-apply without LLM
7. ⬜ Law update proposals generated automatically
8. ⬜ Senate integration: amendments flow back into rules
9. ⬜ Cost per commit < $0.01 after warmup

## Boundaries with Other Systems

| System | Relationship |
|--------|--------------|
| **Centurion** | Calls Truthsayer. Truthsayer is a tool, Centurion is the gate. |
| **Senate** | Writes the laws Truthsayer enforces. Rule amendments come from Senate verdicts. |
| **Learning Loop** | Analyzes run quality. Truthsayer findings are one signal among many. |
| **Oathkeeper** | Tracks commitments. Orthogonal — Truthsayer is about code, Oathkeeper is about promises. |

## Next Steps (Priority Order)

1. **Implement Senate verdict** — Amend `silent-fallback` for trap contexts (per verdict `quick-1771535739`)
2. **Build `truthsayer judge`** — Core judgment command
3. **Implement precedent storage** — JSON file, simple schema
4. **Wire LLM calls** — Claude Haiku for cost control
5. **Test warmup cycle** — Run against Agora repos, build precedent base
6. **Senate integration** — Auto-generate law update proposals

## Mythology

Truthsayer walks the Agora in dark robes stitched with golden text — all 88 rules, woven into the fabric. A bronze monocle over one eye, a red quill in his hand, and a cracked mirror that shows two layers: the beautiful surface, and the rot underneath.

He sees what linters miss. The `except: pass` hiding behind valid syntax. The `|| true` that swallows a failure you'll regret at 3am. The law is literally part of him.

He doesn't make the laws. The Senate does that. He doesn't guard the gate. Centurion does that. Truthsayer enforces. That's enough for one character.
