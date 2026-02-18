# Truthsayer Build Plan

## Context

Truthsayer is a Go CLI anti-pattern scanner at `$HOME/truthsayer/`. It detects silent fallbacks, swallowed errors, bad defaults, and other patterns that mask failures — exactly the kind of bug that caused our dispatch.sh model routing disaster.

**PRD:** `$HOME/truthsayer/docs/PRD.md` (602 lines, definitive spec)
**Progress:** `$HOME/truthsayer/progress_truthsayer.txt`

## Current State (2026-02-13 17:48 UTC)

- **Build:** ✅ Compiles clean, binary at `$HOME/truthsayer/truthsayer`
- **Tests:** ✅ All passing (`go test ./...` — 9 packages, 0 failures)
- **Rules:** 16 of 22 implemented and registered
- **CLI commands:** scan, check, report, watch, hook, ci, doctor, rules — all exist and work
- **Phase 1:** ✅ Complete (build fixed, config system works, exclude dirs, severity overrides)
- **Phase 2:** 🔶 14/20 rules done (see breakdown below)

### Implemented Rules (16 total)

**Pre-existing (2):**
1. `silent-fallback.empty-error-check` — AST: `if err != nil { return nil }` without logging
2. `bad-defaults.missing-pipefail` — Regex: bash script without `set -euo pipefail`

**Added 2026-02-13 (14):**
3. `silent-fallback.hidden-failure-bash` — Regex: `|| true`, `2>/dev/null`, `|| :` (`hidden_failure_bash.go`)
4. `config-smells.hardcoded-path` — Regex: `/home/user/` in scripts/configs (`hardcoded_path.go`)
5. `bad-defaults.unvalidated-env-bash` — Regex: `${VAR:-default}` silent fallback (`unvalidated_env_bash.go`)
6. `config-smells.secret-in-config` — Regex: `password=`, `token=` inline (`secret_in_config.go`)
7. `silent-fallback.no-err-trap` — Regex: `set -e` without `trap ERR` (`no_err_trap.go`)
8. `silent-fallback.ignored-error` — AST: error assigned to `_` (`ignored_error.go`)
9. `error-context.unwrapped-error` — AST: bare `return err` (`unwrapped_error.go`)
10. `error-context.generic-message` — AST: `errors.New("failed")` (`generic_error.go`)
11. `bad-defaults.no-timeout` — AST: `http.Client{}` no timeout (`no_timeout.go`)
12. `bad-defaults.unvalidated-env-go` — AST: `os.Getenv` without check (`unvalidated_env_go.go`)
13. `trace-gaps.long-function-no-log` — AST: >20 lines no logging (`long_function_no_log.go`)
14. `trace-gaps.error-path-no-log` — AST: err branch no log (`error_path_no_log.go`)
15. `mock-leakage.mock-import-non-test` — AST: testify in prod code (`mock_leakage.go`)
16. `mock-leakage.test-fixture-ref` — Regex: `testdata/` in non-test (`mock_leakage.go`)

### Test scan results (our workspace scripts)
```
Summary: 2 errors, 112 warnings, 27 info (34 files scanned in 6ms)
Categories: silent-fallback: 118, bad-defaults: 23
```

### Remaining Rules (6 from PRD, see PRD section 9)
- `silent-fallback.bare-return-on-error`
- `error-context.http-200-on-error`
- `error-context.nil-on-error`
- `trace-gaps.no-request-id`
- `trace-gaps.no-stderr-capture`
- `bad-defaults.magic-number`
- `config-smells.missing-gitignore`
- `mock-leakage.debug-guard`

## Phase 3: Remaining CLI & Features (US-014 → US-019)

These CLI commands already exist from earlier ralph work:
- `rules` command — lists all rules with IDs, descriptions, severity ✅
- `rules --enabled` — lists only active rules ✅
- `hook` / `hook install` — git pre-commit hook ✅
- `ci init` — GitHub Actions workflow template ✅
- `doctor` — check installation, config, rule count ✅
- `--version` — needs verification

**Status:** Likely mostly done. Verify each works end-to-end after rules are complete.

## Phase 4: Integration & Testing (US-020 → US-021)

- **US-020:** Integration tests & benchmarks (10k LOC < 5s)
- **US-021:** Example config, documentation, help text polish

## Phase 5: Wire Into Our System

1. **Add truthsayer to verify.sh** — run after agent completion alongside UBS
2. **Add to dispatch pipeline** — truthsayer scan on changed files, results in run records
3. **Create .truthsayer.toml for workspace** — configure rules for our bash-heavy codebase
4. **UBS + Truthsayer combined report** — unified findings from both tools

## Architecture (for cold pickup)

```
cmd/truthsayer/main.go          — entry point
internal/cli/                    — CLI commands (scan, check, report, watch, hook, ci, doctor, rules)
internal/cli/registry.go         — buildEngine() creates configured engine from config
internal/config/                 — TOML config loading (.truthsayer.toml)
internal/engine/engine.go        — concurrent scan orchestration
internal/engine/walker.go        — file walker with exclude dirs/patterns
internal/rules/rule.go           — ASTChecker + RegexChecker interfaces
internal/rules/registry.go       — DefaultRegistry() registers all rules
internal/rules/<rule>.go         — individual rule implementations
internal/scanner/go_scanner.go   — Go AST file scanner
internal/scanner/regex_scanner.go — line-based regex scanner
internal/finding/                — Finding struct, sort, dedup
internal/report/                 — JSON report output
internal/watcher/                — file watcher for watch mode
internal/diff/                   — git diff support
```

### How to add a new rule
1. Create `internal/rules/<name>.go` implementing `ASTChecker` or `RegexChecker`
2. Implement `Meta()` returning Rule struct (ID, Category, Name, Description, Severity, FileTypes, ScanType)
3. Implement `CheckAST()` or `CheckLines()` returning `[]finding.Finding`
4. Register in `DefaultRegistry()` in `internal/rules/registry.go`
5. Add tests in `internal/rules/<name>_test.go`
6. Run `go test ./...` and `go build -o truthsayer ./cmd/truthsayer`

### Rule interfaces
```go
type ASTChecker interface {
    Meta() Rule
    CheckAST(fset *token.FileSet, file *ast.File, lines []string) []finding.Finding
}

type RegexChecker interface {
    Meta() Rule
    CheckLines(path string, lines []string) []finding.Finding
}
```

### Helper functions available in rules package
- `sourceLine(lines, lineNum)` — get source line by 1-based number
- `isErrNilCheck(expr)` — check if expression is `err != nil`
- `isNilReturn(block)` — check if block is `return nil, nil`
- `hasLogCall(block)` — check if block has any log/print calls

## UBS Integration Notes

UBS is installed at `$HOME/.local/bin/ubs` (multi-language scanner).

**How UBS and Truthsayer complement:**
- UBS: broad language coverage, community rules
- Truthsayer: our custom anti-patterns, bash silent defaults, model routing bugs
- Both should run in verify.sh

## Build Commands

```bash
export PATH="$PATH:/usr/local/go/bin"
cd $HOME/truthsayer
go test ./...                    # Run all tests
go build -o truthsayer ./cmd/truthsayer  # Build binary
./truthsayer scan <path>         # Test scan
./truthsayer rules               # List all 16 rules
./truthsayer scan $HOME/.openclaw/workspace/scripts/  # Test against our scripts
```

## Working Mode

Perttu wants collaborative work — no blind agent dispatch. Document everything for context continuity across resets.

## Key Files

| File | Purpose |
|------|---------|
| `$HOME/truthsayer/docs/PRD.md` | Definitive spec (602 lines) |
| `$HOME/truthsayer/progress_truthsayer.txt` | Build progress log |
| `$HOME/truthsayer/internal/rules/` | Rule implementations |
| `$HOME/truthsayer/internal/rules/registry.go` | DefaultRegistry — where rules get registered |
| `$HOME/truthsayer/internal/scanner/` | Go AST + regex scanners |
| `$HOME/truthsayer/internal/engine/` | Scan engine + file walker |
| `$HOME/truthsayer/internal/cli/` | CLI commands |
| `~/.openclaw/workspace/scripts/verify.sh` | Where truthsayer gets wired in (Phase 5) |
