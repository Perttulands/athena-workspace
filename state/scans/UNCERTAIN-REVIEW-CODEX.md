# UNCERTAIN Findings Review (Codex)

Scope reviewed from `state/scans/tools-20260220.json` (excluding `beads/*`, matching `UNCERTAIN.md`):
- `silent-fallback.hidden-failure-bash`: 163
- `bad-defaults.unvalidated-env-bash`: 102
- `error-context.unwrapped-error`: 166
- Total: 431

Method:
- Pulled all finding rows by rule.
- Grouped by repo/file to identify dominant patterns.
- Sampled and inspected source in `/home/chrote/athena/tools/*`.

## 1) `silent-fallback.hidden-failure-bash` (163)

### Classification
- Real bugs: **2**
- Acceptable patterns: **161**

### Real bugs

1. `truthsayer/scripts/judge.sh:125`
```bash
echo "$JUDGMENT" | jq -c '.[]' 2>/dev/null | while IFS= read -r j; do
```
Issue: JSON parse failure is silently dropped, so unprecedented findings may be skipped.

2. `truthsayer/scripts/judge.sh:148`
```bash
LLM_VERDICTS=$(echo "$JUDGMENT" | jq '[.[] | {rule, file, verdict, reasoning, source: "judge"}]' 2>/dev/null || echo '[]')
```
Issue: fallback to `[]` can produce a false clean result when LLM output is malformed.

### Acceptable patterns (examples)

- Intentional best-effort operations with explicit reason:
`argus/actions.sh:469`
```bash
relay_publish_problem "critical" "alert" "$message" "alert" || true # REASON: relay publishing is best-effort and must not block alert handling.
```

- Expected probe failures handled safely:
`argus/collectors.sh:167`
```bash
orphan_count=$(pgrep -cf 'node.*--test' 2>/dev/null) || orphan_count=0 # REASON: no matches or pgrep limitations should map to zero.
```

- Test harness intentionally capturing non-zero exits:
`learning-loop/tests/test-manage-patterns.sh:57`
```bash
usage_output="$($MANAGE 2>&1 || true)"
```

### Fixes

- In `truthsayer/scripts/judge.sh`, fail closed if `$JUDGMENT` is not valid JSON array/object before verdict extraction.
- Replace silent fallback with explicit error:
  - `if ! echo "$JUDGMENT" | jq -e 'type=="array"' >/dev/null; then exit 1; fi`
- Keep current Argus/learning-loop best-effort cases; they are mostly justified by in-line `# REASON` comments.

## 2) `bad-defaults.unvalidated-env-bash` (102)

### Classification
- Real/likely bugs: **20**
- Acceptable patterns: **82**

### Real/likely bugs

1. Numeric env used in arithmetic/timeouts without validation (`argus/actions.sh`):
`argus/actions.sh:23-24,26,28,31-33`
```bash
ARGUS_BEAD_REPEAT_THRESHOLD="${ARGUS_BEAD_REPEAT_THRESHOLD:-3}"
ARGUS_BEAD_REPEAT_WINDOW_SECONDS="${ARGUS_BEAD_REPEAT_WINDOW_SECONDS:-86400}"
ARGUS_DEDUP_WINDOW="${ARGUS_DEDUP_WINDOW:-3600}"
ARGUS_DISK_CLEAN_MAX_AGE_DAYS="${ARGUS_DISK_CLEAN_MAX_AGE_DAYS:-7}"
ARGUS_RESTART_BACKOFF_SECOND_DELAY="${ARGUS_RESTART_BACKOFF_SECOND_DELAY:-60}"
```
Used later in arithmetic:
```bash
cutoff=$((now - ARGUS_BEAD_REPEAT_WINDOW_SECONDS))
if (( now - last_seen < ARGUS_DEDUP_WINDOW )); then
```
Risk: invalid values can break runtime behavior under `set -euo pipefail`.

2. Unvalidated float sample rate:
`learning-loop/scripts/feedback-collector.sh:151,168,178`
```bash
JUDGE_SAMPLE_RATE="${JUDGE_SAMPLE_RATE:-0.25}"
if echo "$JUDGE_SAMPLE_RATE <= 0" | bc -l | grep -q '^1'; then
threshold="$(echo "$JUDGE_SAMPLE_RATE * 1000" | bc -l | awk '{printf "%d", $1}')"
```
Risk: non-numeric value can cause parse failures and abort the script.

3. Retention days used directly in `find -mtime`:
`learning-loop/scripts/backup-state.sh:18,43`
```bash
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
find "$BACKUP_DIR" ... -mtime "+$BACKUP_RETENTION_DAYS" -delete
```
Risk: malformed value breaks backup cleanup path.

4. Boolean gating inconsistency (`NO_AUTO_PROMOTE`):
`learning-loop/scripts/ab-tests.sh:16`
```bash
NO_AUTO_PROMOTE="${NO_AUTO_PROMOTE:-true}"
```
`learning-loop/scripts/guardrails.sh:218`
```bash
if [[ "${NO_AUTO_PROMOTE:-false}" == "true" ]]; then
```
Risk: default mismatch across scripts causes inconsistent promotion behavior.

### Acceptable patterns (examples)

- Path defaults are expected configuration points:
`learning-loop/scripts/score-templates.sh:12`
```bash
SCORES_DIR="${SCORES_DIR:-$PROJECT_DIR/state/scores}"
```

- Safe fallback with prerequisite check:
`relay/install-service.sh:7-10`
```bash
if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
  : "${HOME:?HOME is required when XDG_CONFIG_HOME is unset}"
fi
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
```

- Model default in script-level wrapper is acceptable:
`truthsayer/scripts/judge.sh:12`
```bash
MODEL="${TRUTHSAYER_JUDGE_MODEL:-claude-haiku}"
```

### Fixes

- Add shared env validators in affected scripts:
  - `require_int_env VAR min max`
  - `require_float_env VAR min max`
  - `parse_bool_env VAR default`
- Validate early after env declarations and emit clear errors.
- Normalize `NO_AUTO_PROMOTE` handling in one helper used by both `ab-tests.sh` and `guardrails.sh`.

## 3) `error-context.unwrapped-error` (166)

### Classification
- Actionable context bugs (diagnostic quality): **74**
- Acceptable pass-throughs: **92**

### Actionable context bugs (examples)

1. File-scan pipeline loses path context:
`truthsayer/internal/engine/engine.go:266`
```go
results, goLines, err := e.goScanner.Scan(path)
if err != nil {
    return nil, err
}
```
Better:
```go
return nil, fmt.Errorf("scan go file %s: %w", path, err)
```

2. CLI command boundaries return raw errors without operation context:
`ludus-magnus/cmd/run.go:85`
```go
result, err := engine.Execute(cmd.Context(), request)
if err != nil {
    return err
}
```
Better:
```go
return fmt.Errorf("run session %s lineage %s: %w", sessionID, selectedLineage, err)
```

3. Store operations return raw IO/JSON errors where path/op context helps:
`relay/internal/store/store.go:49-52`
```go
if err := os.MkdirAll(dir, 0755); err != nil {
    return err
}
if err := atomicWriteJSON(filepath.Join(dir, "meta.json"), meta); err != nil {
    return err
}
```
Better:
```go
return fmt.Errorf("register agent %s: write meta: %w", meta.Name, err)
```

### Acceptable pass-through patterns (examples)

- Low-level helper returning sentinel/typed error intentionally:
`oathkeeper/pkg/beads/beads.go:147`
```go
return Bead{}, err
```
(Caller may branch on parser/command error and preserve exact cause.)

- Parse helpers that already receive contextual errors from lower functions:
`oathkeeper/cmd/oathkeeper/main.go:623`
```go
if err := parseFlags(fs, args, serveUsage); err != nil {
    return serveOptions{}, err
}
```
(`parseFlags` already formats user-facing context.)

### Fixes

- Prioritize wrapping at user-facing boundaries first:
  - `ludus-magnus/cmd/*.go`
  - `truthsayer/internal/engine/engine.go`
  - `relay/pkg/client/client.go`
- Keep pass-through in narrow leaf helpers where caller intentionally handles sentinels.
- Suggested wrapping rule:
  - every `return err` in exported/public boundary functions should include operation + key identifier (`path`, `sessionID`, `agent`, `caseID`).

## Recommended next patch set

1. **High priority**
- `truthsayer/scripts/judge.sh`: remove fail-open JSON fallbacks (2 real bugs).

2. **Medium priority**
- Add env validation helpers + apply to:
  - `argus/actions.sh`
  - `argus/argus.sh`
  - `learning-loop/scripts/feedback-collector.sh`
  - `learning-loop/scripts/backup-state.sh`
  - `learning-loop/scripts/ab-tests.sh` + `learning-loop/scripts/guardrails.sh`

3. **Quality pass**
- Wrap uncontextualized errors in `ludus-magnus/cmd/*`, `truthsayer/internal/engine/engine.go`, and selected `relay/internal/store/store.go` entrypoints.
