---
name: bug-scanner
description: Scan code for bugs and anti-patterns. Use UBS for multi-language static analysis and Truthsayer for Go/bash anti-patterns.
---

# Bug Scanning

Two tools, different scopes. Both wired into `verify.sh`.

## UBS (Universal Bug Scanner)

Multi-language static analysis. Auto-detects languages.

```bash
ubs .                        # Full scan
ubs --staged                 # Staged files only (pre-commit)
ubs --diff                   # Modified files only (quick check)
ubs --only=js,python .       # Restrict languages
ubs --format=json .          # Machine-readable
ubs --html-report=out.html . # HTML report
```

Supports: JS, Python, C++, Rust, Go, Java, Ruby, Swift.

## Truthsayer

Anti-pattern scanner for Go and bash. 24 rules, 6 categories.

```bash
truthsayer scan <dir>              # Scan directory
truthsayer scan --format json .    # JSON output
truthsayer check <file>            # Single file
truthsayer rules                   # List all rules
```

| Category | Catches |
|----------|---------|
| silent-fallback | Swallowed errors, ignored returns, bare returns |
| error-context | Generic messages, unwrapped errors, HTTP 200 on error |
| trace-gaps | No logging, missing request IDs |
| mock-leakage | Test imports in prod, debug guards |
| bad-defaults | Missing timeouts, no pipefail, magic numbers |
| config-smells | Hardcoded paths, secrets in config |

Truthsayer errors fail the verify.sh quality gate. Warnings don't.
