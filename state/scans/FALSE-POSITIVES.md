# False Positives — Patterns to Exclude

These findings are false positives due to test code, intentional patterns, or scanner limitations.

## code-quality.unreachable-code (798 findings)
Most are in test fixtures or intentional dead code paths.
**Action:** Add `exclude_patterns` for test fixture directories.

### Sample locations:
- ludus-magnus: 144 findings
- oathkeeper: 38 findings
- relay: 29 findings
- senate: 29 findings
- truthsayer: 558 findings

## security.sql-injection (12 findings)
Test fixtures containing intentional SQL examples.
**Action:** Disable for test files or add REASON comments.

- `oathkeeper/pkg/storage/storage.go:217`
- `truthsayer/internal/engine/benchmark_test.go:90`
- `truthsayer/internal/engine/benchmark_test.go:102`
- `truthsayer/internal/engine/benchmark_test.go:109`
- `truthsayer/internal/engine/benchmark_test.go:116`
- `truthsayer/internal/engine/benchmark_test.go:127`
- `truthsayer/internal/engine/benchmark_test.go:601`
- `truthsayer/internal/engine/benchmark_test.go:606`
- `truthsayer/internal/engine/benchmark_test.go:617`
- `truthsayer/internal/engine/benchmark_test.go:630`
- `truthsayer/internal/rules/security_regex_rules.go:460`
- `truthsayer/internal/rules/security_regex_rules.go:462`

## config-smells.hardcoded-credentials (11 findings)
Test fixtures with intentional credential examples.
**Action:** Disable for test files.

- `truthsayer/internal/rules/py_regex_config_smells_test.go:10`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:11`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:12`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:13`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:26`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:36`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:37`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:38`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:69`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:88`
- `truthsayer/internal/rules/py_regex_config_smells_test.go:89`
