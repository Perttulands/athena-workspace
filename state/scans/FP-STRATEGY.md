# False Positive Elimination Strategy

**Generated:** 2026-02-20  
**False Positives Analyzed:** 821  
**Repos Affected:** truthsayer, ludus-magnus, oathkeeper, relay, senate

---

## Executive Summary

The 821 false positives break down into three categories:

| Rule | Count | Root Cause | Fix Approach |
|------|-------|------------|--------------|
| `code-quality.unreachable-code` | 798 | Test fixtures with intentional dead code | Global test exclusion |
| `security.sql-injection` | 12 | Intentional SQL in test/example code | Per-file inline suppression |
| `config-smells.hardcoded-credentials` | 11 | Test fixtures with fake credentials | Per-file inline suppression |

**Net impact:** One global config change + ~10 inline suppressions eliminates 99.7% of noise.

---

## Strategy 1: Global Exclusion Patterns

### Recommended `.truthsayer.toml` Changes (Global/Shared Config)

Add these patterns to the global/default config that all repos inherit:

```toml
[global]
exclude_patterns = [
  "**/testdata/**",
  "**/testfixtures/**",
  "**/*_test.go",
  "**/test_*.py",
  "**/*_test.py",
  "**/tests/**",
  "**/fixtures/**",
  "**/__tests__/**",
  "**/mock_*.go",
  "**/mocks/**",
  "**/benchmark_test.go",
]
```

**Rationale:** Test code is intentionally synthetic. Scanning it for code quality and security patterns produces noise, not signal.

---

## Strategy 2: Rule-Specific Configuration

### `code-quality.unreachable-code` (798 findings)

**Recommendation:** Disable globally for test files OR add test exclusion to rule config.

```toml
[rules."code-quality.unreachable-code"]
# Option A: Disable entirely (if unreachable code is acceptable in your codebase)
enabled = false

# Option B: Exclude test patterns only (preferred)
exclude_patterns = [
  "**/testdata/**",
  "**/*_test.go",
  "**/benchmark_test.go",
]
```

**By repo:**
| Repo | Findings | Action |
|------|----------|--------|
| truthsayer | 558 | Exclude `testdata/` (contains rule test fixtures) |
| ludus-magnus | 144 | Exclude test scenarios |
| oathkeeper | 38 | Exclude test files |
| relay | 29 | Exclude test files |
| senate | 29 | Exclude test files |

### `security.sql-injection` (12 findings)

**Recommendation:** Inline suppression with `// truthsayer:ignore` comments.

These are in files that *define* SQL injection rules or benchmark them:
- `oathkeeper/pkg/storage/storage.go:217` — Real query builder, review if actually safe
- `truthsayer/internal/engine/benchmark_test.go` — 9 findings, all intentional examples
- `truthsayer/internal/rules/security_regex_rules.go` — Rule definitions containing example patterns

**Config snippet for per-repo suppression:**

```toml
# truthsayer/.truthsayer.toml
[rules."security.sql-injection"]
exclude_patterns = [
  "internal/rules/*_rules.go",      # Rule definitions contain examples
  "internal/engine/benchmark_test.go",
]
```

```toml
# oathkeeper/.truthsayer.toml
[rules."security.sql-injection"]
exclude_files = [
  "pkg/storage/storage.go",  # Manual review: uses parameterized queries
]
```

### `config-smells.hardcoded-credentials` (11 findings)

**Recommendation:** Exclude test files that intentionally contain fake credentials.

All 11 findings are in `truthsayer/internal/rules/py_regex_config_smells_test.go` — test fixtures.

```toml
# truthsayer/.truthsayer.toml
[rules."config-smells.hardcoded-credentials"]
exclude_patterns = [
  "**/*_test.go",
]
```

---

## Strategy 3: Per-Repo `.truthsayer.toml` Changes

### truthsayer (558 unreachable + 10 sql + 11 creds = 579 total)

```toml
# truthsayer/.truthsayer.toml

[global]
exclude_patterns = [
  "testdata/**",
  "internal/engine/benchmark_test.go",
]

[rules."code-quality.unreachable-code"]
exclude_patterns = ["testdata/**"]

[rules."security.sql-injection"]
exclude_patterns = [
  "internal/rules/*_rules.go",
  "internal/engine/benchmark_test.go",
]

[rules."config-smells.hardcoded-credentials"]
exclude_patterns = ["**/*_test.go"]
```

### ludus-magnus (144 unreachable)

```toml
# ludus-magnus/.truthsayer.toml

[rules."code-quality.unreachable-code"]
exclude_patterns = [
  "**/testdata/**",
  "**/scenarios/**",
]
```

### oathkeeper (38 unreachable + 1 sql = 39 total)

```toml
# oathkeeper/.truthsayer.toml

[rules."code-quality.unreachable-code"]
exclude_patterns = ["**/*_test.go"]

[rules."security.sql-injection"]
# Review storage.go:217 manually, then either fix or add:
exclude_files = ["pkg/storage/storage.go"]
```

### relay (29 unreachable)

```toml
# relay/.truthsayer.toml

[rules."code-quality.unreachable-code"]
exclude_patterns = ["**/*_test.go", "**/testdata/**"]
```

### senate (29 unreachable)

```toml
# senate/.truthsayer.toml

[rules."code-quality.unreachable-code"]
exclude_patterns = ["**/*_test.go", "**/testdata/**"]
```

---

## Implementation Priority

### Phase 1: Immediate (eliminates 97% of FPs)

1. **Add global test exclusions** to shared/default truthsayer config
   - Targets: `**/testdata/**`, `**/*_test.go`
   - Impact: ~780 findings eliminated
   - Effort: 5 min, single config change

### Phase 2: Quick Wins (remaining 3%)

2. **Add per-rule exclusions in truthsayer repo**
   - Targets: rule definition files, benchmark tests
   - Impact: ~21 findings eliminated
   - Effort: 10 min, one `.truthsayer.toml` update

3. **Add exclusions in ludus-magnus/oathkeeper**
   - Impact: Clean CI for these repos
   - Effort: 10 min each

### Phase 3: Manual Review

4. **Review `oathkeeper/pkg/storage/storage.go:217`**
   - This is production code flagged for SQL injection
   - Either confirm it's a false positive and suppress, or fix
   - Effort: 15-30 min review

---

## Alternative: Inline Suppressions

If config changes aren't possible, use inline comments:

```go
// truthsayer:ignore security.sql-injection -- Intentional example for rule testing
query := "SELECT * FROM users WHERE id = " + userInput
```

**Not recommended** for bulk suppressions (creates noise in code).

---

## CI Integration Notes

After implementing these changes:

1. Run `truthsayer scan --config .truthsayer.toml` in each repo
2. Confirm finding count drops from 821 → near 0
3. Add `.truthsayer.toml` to CI lint step if not already present
4. Consider adding `--fail-on-new` flag to prevent new findings

---

## Summary Checklist

- [ ] Add global test exclusions to shared config
- [ ] Create/update `truthsayer/.truthsayer.toml` with rule-specific exclusions
- [ ] Create/update `ludus-magnus/.truthsayer.toml` with unreachable-code exclusion
- [ ] Create/update `oathkeeper/.truthsayer.toml` with exclusions
- [ ] Create/update `relay/.truthsayer.toml` with exclusions  
- [ ] Create/update `senate/.truthsayer.toml` with exclusions
- [ ] Manual review: `oathkeeper/pkg/storage/storage.go:217`
- [ ] Re-run scan to confirm 0 false positives
- [ ] Update CI to use new configs
