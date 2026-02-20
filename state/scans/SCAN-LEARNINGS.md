# Truthsayer Scan Learnings — 2026-02-20

## Overview

Full truthsayer scan of `/home/chrote/athena/tools/` (7 repos, excluding beads).
Total findings: 1616 (after excluding beads repo).

## Results Summary

| Category | Count | Outcome |
|----------|-------|---------|
| Real bugs fixed | 59 | ✅ 5 beads closed |
| False positives | 821 | ✅ Config deployed |
| Uncertain → bugs | ~10 | 🔄 6 beads in progress |
| Uncertain → acceptable | ~420 | ✅ No action needed |

## Key Learnings

### 1. Test Files Generate Most Noise
**Finding:** 97% of false positives (798/821) were `unreachable-code` in test fixtures.
**Action:** Added `*_test.go` and `testdata/` to global exclusions.
**Future:** Always exclude test patterns by default in new repos.

### 2. Some Rules Have 0% Signal
**Finding:** `bad-defaults.unvalidated-env-bash` fired 109 times with 0-20% true positive rate (reviewers disagreed).
**Action:** Disabled globally, but Codex review found edge cases worth validating.
**Learning:** "Disable noisy rule" vs "add validation helpers" is a judgment call. When reviewers disagree, dig into specifics.

### 3. Multi-Reviewer Disagreement is Valuable
**Finding:** Opus and Codex disagreed on:
- `unvalidated-env-bash`: 0% vs 20% bug rate
- `unwrapped-error`: 10% vs 45% actionable
**Learning:** Run 2+ reviewers on uncertain findings. Disagreements highlight edge cases humans should review.

### 4. REASON Comments Work
**Finding:** Argus already had excellent `# REASON:` coverage. Other repos didn't.
**Action:** Added REASON comments to justify intentional `2>/dev/null` patterns.
**Learning:** Document-as-you-go prevents future scan noise.

### 5. Error Wrapping Boundaries Matter
**Finding:** `unwrapped-error` at 166 findings, but only CLI boundaries need wrapping.
**Action:** Wrap at `cmd/*.go` entry points, not internal layers.
**Learning:** Rule should distinguish exported vs internal functions.

## Process Improvements

### What Worked
1. **Categorize first, fix second** — REAL-BUGS.md, FALSE-POSITIVES.md, UNCERTAIN.md
2. **Parallel review** — Opus + Codex caught different issues
3. **Batch by repo** — One agent per repo avoided conflicts
4. **Config before code** — .truthsayer.toml eliminated 97% of noise before manual fixes

### What to Improve
1. **Scan earlier** — Should scan before major refactors, not after
2. **Rule tuning** — `unvalidated-env-bash` needs refinement or removal from default set
3. **Incremental scans** — Use `truthsayer ci` for changed-lines-only in PR checks

## Metrics

| Metric | Value |
|--------|-------|
| Total scan time | ~1 second |
| Files scanned | 248 |
| Beads created | 12 |
| Beads closed | 6 |
| Agent hours | ~2 hours |
| Human review time | ~30 min |

## Recommended Defaults for New Repos

```toml
# .truthsayer.toml
[scan]
exclude_dirs = ["vendor", "node_modules", "testdata", ".beads"]
exclude_patterns = ["*_test.go", "**/__tests__/**"]

[rules]
disable = [
  "bad-defaults.unvalidated-env-bash",  # Too noisy for config-heavy scripts
]
```

## Follow-up Actions

- [ ] Close remaining 6 beads when agents complete
- [ ] Re-run full scan to confirm 0 errors
- [ ] Add truthsayer to CI for all repos
- [ ] Consider PR to truthsayer: narrow `unwrapped-error` to exported functions
- [ ] Close athena-1tp5 (uncertain triage complete)
