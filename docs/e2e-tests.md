# Test Suite

All tests live under `tests/`. Single entry point: `tests/run.sh`.

## Running

```bash
./tests/run.sh              # All e2e tests
./tests/run.sh --unit       # Centurion unit tests (pytest)
./tests/run.sh --all        # Everything
./tests/run.sh tests/e2e/test-beads-lifecycle.sh  # Specific test
```

## Structure

```
tests/
├── run.sh                         Single entry point
├── fixtures/                      Test data (prompts, etc.)
├── e2e/                           Bash integration tests
│   ├── helpers.sh                 Assertions + utilities
│   ├── test-argus.sh              Argus health checks
│   ├── test-beads-lifecycle.sh    br create → show → close
│   ├── test-dispatch.sh           Full dispatch pipeline (E2E_RESULT markers)
│   ├── test-dispatch-lifecycle.sh Full dispatch with isolated socket
│   ├── test-services.sh           Service health (gateway, agent mail, athena-web)
│   ├── test-tools.sh              CLI tool availability
│   ├── test-truthsayer-scan.sh    Truthsayer JSON output
│   ├── test-wake-gateway.sh       Wake signal delivery
│   └── test-workspace.sh          Core file/directory existence
└── unit/                          Python unit tests
    └── test_centurion_*.py        Centurion merge orchestration (13 files, pytest)
```

## E2E Tests

| Test | What it verifies | Duration |
|------|-----------------|----------|
| `test-beads-lifecycle.sh` | `br` create → show → close → delete | ~1s |
| `test-wake-gateway.sh` | Wake signal sends, returns JSON | ~2s |
| `test-truthsayer-scan.sh` | Truthsayer scan produces valid JSON | ~5s |
| `test-workspace.sh` | Core files exist (AGENTS.md, etc.) | ~1s |
| `test-tools.sh` | CLI tools installed and responsive | ~10s |
| `test-services.sh` | Services responding on expected ports | ~5s |
| `test-argus.sh` | Argus service running, logs recent | ~5s |
| `test-dispatch.sh` | Full pipeline with E2E_RESULT markers | ~60-300s |
| `test-dispatch-lifecycle.sh` | Dispatch with isolated tmux socket | ~60-120s |

## Conventions

- All tests use `set -euo pipefail`
- Exit 0 = pass, non-zero = fail
- Tests clean up after themselves (trap EXIT)
- Unavailable tools → print SKIP, exit 0
- `helpers.sh` provides assertions: `assert_not_empty`, `assert_equals`, `assert_contains`, `assert_file_exists`, `assert_json_file_field`, `assert_json_valid`, `assert_tmux_session_exists`
- `helpers.sh` provides utilities: `generate_test_id`, `wait_for_terminal_status`, `cleanup_test_bead`
- Dispatch tests use isolated tmux sockets to avoid interfering with real agents
