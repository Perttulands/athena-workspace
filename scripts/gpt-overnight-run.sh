#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_OUTPUT_ROOT="$REPO_ROOT/GPT overnight/runs"
DEFAULT_DURATION_SECONDS=10800
DEFAULT_INTERVAL_SECONDS=900

DURATION_SECONDS="$DEFAULT_DURATION_SECONDS"
INTERVAL_SECONDS="$DEFAULT_INTERVAL_SECONDS"
OUTPUT_ROOT="$DEFAULT_OUTPUT_ROOT"
RUN_LABEL="$(date -u +%Y%m%dT%H%M%SZ)"
HOME_ROOT="${HOME:-/home/perttu}"

ATHENA_REPO="$REPO_ROOT"
MANAGED_SERVICES=(
    "openclaw-gateway.service"
    "athena-web.service"
    "argus.service"
)
TARGET_PORTS=(18500 9000 8765)

# Detached tmux sessions may not carry user bus vars.
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
export XDG_RUNTIME_DIR
export DBUS_SESSION_BUS_ADDRESS

usage() {
    cat <<'EOF'
Usage: gpt-overnight-run.sh [OPTIONS]

Runs a long-form systems analysis capture loop and writes artifacts under:
  GPT overnight/runs/<timestamp>/

OPTIONS:
  --duration-seconds N   Total runtime in seconds (default: 10800 = 3h)
  --interval-seconds N   Snapshot interval in seconds (default: 900 = 15m)
  --output-root PATH     Base output path (default: <repo>/GPT overnight/runs)
  --run-label LABEL      Override run label (default: UTC timestamp)
  --home-root PATH       Root path to scan for git repos (default: $HOME)
  --help                 Show this message

Examples:
  ./scripts/gpt-overnight-run.sh
  ./scripts/gpt-overnight-run.sh --duration-seconds 14400 --interval-seconds 600
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration-seconds)
            DURATION_SECONDS="$2"
            shift 2
            ;;
        --interval-seconds)
            INTERVAL_SECONDS="$2"
            shift 2
            ;;
        --output-root)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --run-label)
            RUN_LABEL="$2"
            shift 2
            ;;
        --home-root)
            HOME_ROOT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$DURATION_SECONDS" -lt 1 ]]; then
    echo "Error: --duration-seconds must be a positive integer" >&2
    exit 1
fi
if [[ ! "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_SECONDS" -lt 30 ]]; then
    echo "Error: --interval-seconds must be an integer >= 30" >&2
    exit 1
fi

RUN_DIR="$OUTPUT_ROOT/$RUN_LABEL"
SNAPSHOTS_DIR="$RUN_DIR/snapshots"
mkdir -p "$SNAPSHOTS_DIR"

RUN_LOG="$RUN_DIR/run.log"
TIMELINE_FILE="$RUN_DIR/timeline.tsv"
MANIFEST_FILE="$RUN_DIR/manifest.txt"
SUMMARY_FILE="$RUN_DIR/final-summary.md"
RECOMMENDATIONS_FILE="$RUN_DIR/improvements.md"

touch "$RUN_LOG" "$TIMELINE_FILE"

log() {
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf "[%s] %s\n" "$ts" "$*" | tee -a "$RUN_LOG"
}

capture_cmd() {
    local output_file="$1"
    shift
    {
        printf '$'
        printf " %q" "$@"
        printf "\n"
    } >"$output_file"
    if "$@" >>"$output_file" 2>&1; then
        printf "\n[exit_code] 0\n" >>"$output_file"
    else
        local rc=$?
        printf "\n[exit_code] %s\n" "$rc" >>"$output_file"
    fi
}

capture_json_cmd() {
    local output_file="$1"
    shift
    if "$@" >"$output_file" 2>"${output_file}.stderr"; then
        return 0
    fi
    local rc=$?
    printf '{"error":"command_failed","exit_code":%s}\n' "$rc" >"$output_file"
    return 0
}

capture_tooling_versions() {
    local output_file="$1"
    {
        if command -v bd >/dev/null 2>&1; then
            echo "bd:$(bd --version 2>/dev/null | head -n 1)"
        else
            echo "bd:missing"
        fi

        if command -v br >/dev/null 2>&1; then
            echo "br:present"
        else
            echo "br:missing"
        fi

        if command -v dolt >/dev/null 2>&1; then
            echo "dolt:$(dolt version 2>/dev/null | head -n 1)"
        else
            echo "dolt:missing"
        fi

        if command -v tmux >/dev/null 2>&1; then
            echo "tmux:$(tmux -V 2>/dev/null)"
        else
            echo "tmux:missing"
        fi
    } >"$output_file"
}

discover_repos() {
    find "$HOME_ROOT" -mindepth 1 -maxdepth 2 -type d -name .git 2>/dev/null \
        | sed 's#/\.git$##' \
        | sort
}

repo_status_snapshot() {
    local output_file="$1"
    {
        printf "repo\tbranch\tdirty\tstaged\tunstaged\tuntracked\tahead\tbehind\tlast_commit\n"
        while IFS= read -r repo; do
            local branch status_lines dirty staged unstaged untracked upstream_counts ahead behind last_commit
            branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
            status_lines="$(git -C "$repo" status --porcelain 2>/dev/null || true)"

            if [[ -n "$status_lines" ]]; then
                dirty="$(printf "%s\n" "$status_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
            else
                dirty="0"
            fi

            staged="$(printf "%s\n" "$status_lines" | awk 'substr($0,1,1) !~ /[ ?]/ {n++} END {print n+0}')"
            unstaged="$(printf "%s\n" "$status_lines" | awk 'substr($0,2,1) != " " && substr($0,1,1) != "?" {n++} END {print n+0}')"
            untracked="$(printf "%s\n" "$status_lines" | awk '/^\?\?/ {n++} END {print n+0}')"

            ahead="-"
            behind="-"
            if upstream_counts="$(git -C "$repo" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)"; then
                behind="$(awk '{print $1}' <<<"$upstream_counts")"
                ahead="$(awk '{print $2}' <<<"$upstream_counts")"
            fi

            last_commit="$(git -C "$repo" log -1 --pretty=format:'%h %cs %s' 2>/dev/null || echo "no-commit")"
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$repo" "$branch" "$dirty" "$staged" "$unstaged" "$untracked" "$ahead" "$behind" "$last_commit"
        done < <(discover_repos)
    } >"$output_file"
}

collect_snapshot() {
    local label="$1"
    local snapshot_dir="$SNAPSHOTS_DIR/$label"
    mkdir -p "$snapshot_dir"

    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf "%s\t%s\n" "$now" "$label" >>"$TIMELINE_FILE"
    log "Collecting snapshot: $label"

    capture_cmd "$snapshot_dir/time.txt" date -u
    capture_cmd "$snapshot_dir/uptime.txt" uptime
    capture_cmd "$snapshot_dir/loadavg.txt" cat /proc/loadavg
    capture_cmd "$snapshot_dir/memory.txt" free -h
    capture_cmd "$snapshot_dir/disk-home.txt" df -P "$HOME_ROOT"
    capture_cmd "$snapshot_dir/process-top-cpu.txt" bash -lc "ps -eo pid,ppid,comm,%cpu,%mem,etimes --sort=-%cpu | head -n 30"
    capture_cmd "$snapshot_dir/listening-ports.txt" ss -ltnp
    capture_cmd "$snapshot_dir/systemd-user-services.txt" systemctl --user list-units --type=service --all
    capture_cmd "$snapshot_dir/systemd-system-services.txt" systemctl list-units --type=service --all
    capture_cmd "$snapshot_dir/systemd-targeted-user-services.txt" bash -lc "systemctl --user list-units --type=service --all | rg -i 'openclaw|athena|argus|relay|truth|oath|gateway|bead|br|bd' || true"
    capture_cmd "$snapshot_dir/systemd-targeted-system-services.txt" bash -lc "systemctl list-units --type=service --all | rg -i 'openclaw|athena|argus|relay|truth|oath|gateway|bead|br|bd' || true"
    capture_cmd "$snapshot_dir/ports-targeted.txt" bash -lc "ss -ltnp | rg ':(18500|9000|8765)\\b' || true"

    for service in "${MANAGED_SERVICES[@]}"; do
        capture_cmd "$snapshot_dir/service-user-$service.txt" systemctl --user status "$service" --no-pager
        capture_cmd "$snapshot_dir/service-system-$service.txt" systemctl status "$service" --no-pager
    done

    if [[ -x "$ATHENA_REPO/scripts/prd-lint.sh" ]]; then
        capture_json_cmd "$snapshot_dir/athena-prd-lint.json" "$ATHENA_REPO/scripts/prd-lint.sh" --json
    fi
    if [[ -x "$ATHENA_REPO/scripts/doc-gardener.sh" ]]; then
        capture_json_cmd "$snapshot_dir/athena-doc-gardener.json" "$ATHENA_REPO/scripts/doc-gardener.sh" --json
    fi
    if [[ -x "$ATHENA_REPO/scripts/lint-no-hidden-workspace.sh" ]]; then
        capture_cmd "$snapshot_dir/athena-hidden-workspace-lint.txt" "$ATHENA_REPO/scripts/lint-no-hidden-workspace.sh"
    fi
    if [[ -x "$ATHENA_REPO/tests/e2e/test-services.sh" ]]; then
        capture_cmd "$snapshot_dir/athena-e2e-services.txt" "$ATHENA_REPO/tests/e2e/test-services.sh"
    fi

    capture_tooling_versions "$snapshot_dir/tooling-versions.txt"
    if command -v bd >/dev/null 2>&1; then
        capture_json_cmd "$snapshot_dir/bd-status.json" bd status --json
    fi
    if command -v br >/dev/null 2>&1; then
        capture_cmd "$snapshot_dir/br-help.txt" br --help
    fi

    repo_status_snapshot "$snapshot_dir/repo-status.tsv"
}

extract_json_count() {
    local file="$1"
    local jq_expr="$2"
    if [[ ! -f "$file" ]]; then
        echo "n/a"
        return
    fi
    jq -r "$jq_expr" "$file" 2>/dev/null || echo "n/a"
}

build_recommendations() {
    local latest_snapshot="$1"

    local dirty_repos prd_issues doc_issues disk_usage bd_open bd_ready br_line dolt_line
    dirty_repos="$(awk -F'\t' 'NR > 1 && $3 + 0 > 0 {c++} END {print c+0}' "$latest_snapshot/repo-status.tsv" 2>/dev/null || echo "0")"
    prd_issues="$(extract_json_count "$latest_snapshot/athena-prd-lint.json" '.summary.total_issues // "n/a"')"
    doc_issues="$(extract_json_count "$latest_snapshot/athena-doc-gardener.json" '.summary.total_issues // .total_issues // "n/a"')"
    bd_open="$(extract_json_count "$latest_snapshot/bd-status.json" '.summary.open_issues // .open_issues // "n/a"')"
    bd_ready="$(extract_json_count "$latest_snapshot/bd-status.json" '.summary.ready_issues // .ready_issues // "n/a"')"
    br_line="$(awk '/^br:/{print; exit}' "$latest_snapshot/tooling-versions.txt" 2>/dev/null || true)"
    dolt_line="$(awk '/^dolt:/{print; exit}' "$latest_snapshot/tooling-versions.txt" 2>/dev/null || true)"
    disk_usage="$(awk 'NR > 1 && $5 ~ /%/ {gsub("%","",$5); print $5; exit}' "$latest_snapshot/disk-home.txt" 2>/dev/null || echo "n/a")"

    {
        echo "# Improvement Suggestions"
        echo
        echo "Generated from latest snapshot: \`$(basename "$latest_snapshot")\`"
        echo
        echo "## Priority Queue"
        echo "1. Stabilize dirty repositories (\`$dirty_repos\` currently non-clean) by classifying each as intentional WIP, archive candidate, or cleanup candidate."
        echo "2. Keep PRD governance green (\`prd-lint issues: $prd_issues\`) and docs drift green (\`doc-gardener issues: $doc_issues\`) as merge gates in CI."
        echo "3. Treat bead flow as control-plane SLO: \`open=$bd_open\`, \`ready=$bd_ready\`; daily triage with explicit block reasons."
        echo "4. Close the beads toolchain gap by aligning \`br\` + \`dolt\` install/runtime expectations before deprecating legacy paths."
        echo "5. Convert host-level checks (services, ports, disk, process pressure) into a dashboard + alert thresholds."
        echo
        echo "## Conditional Actions"
        if [[ "$disk_usage" != "n/a" ]] && [[ "$disk_usage" =~ ^[0-9]+$ ]] && (( disk_usage >= 80 )); then
            echo "- Disk usage is ${disk_usage}%: enforce log rotation and artifact retention cleanup this week."
        else
            echo "- Disk usage is within a normal range (${disk_usage}%). Keep weekly cleanup cadence."
        fi
        if [[ "$dirty_repos" =~ ^[0-9]+$ ]] && (( dirty_repos > 3 )); then
            echo "- Dirty repo count is high (${dirty_repos}). Add nightly \`git status\` drift report and stale branch pruning."
        fi
        if [[ "$prd_issues" != "n/a" ]] && [[ "$prd_issues" =~ ^[0-9]+$ ]] && (( prd_issues > 0 )); then
            echo "- PRD lint has active issues. Block feature starts until canonical PRDs are repaired."
        fi
        if [[ "$doc_issues" != "n/a" ]] && [[ "$doc_issues" =~ ^[0-9]+$ ]] && (( doc_issues > 0 )); then
            echo "- Doc gardener found drift. Route fixes to `docs/archive/` cleanup plus reference corrections."
        fi
        if [[ -n "$dolt_line" ]] && [[ "$dolt_line" == *"missing"* ]]; then
            echo "- Dolt is missing on PATH; document install + bootstrap to avoid broken `br` workflows."
        fi
        if [[ -n "$br_line" ]] && [[ "$br_line" == *"missing"* ]]; then
            echo "- `br` is missing; pin install method and CI guard to prevent mixed bead CLIs."
        fi
    } >"$RECOMMENDATIONS_FILE"
}

write_manifest() {
    {
        echo "run_label=$RUN_LABEL"
        echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "duration_seconds=$DURATION_SECONDS"
        echo "interval_seconds=$INTERVAL_SECONDS"
        echo "repo_root=$REPO_ROOT"
        echo "home_root=$HOME_ROOT"
        echo "output_root=$OUTPUT_ROOT"
        echo "services=${MANAGED_SERVICES[*]}"
        echo "ports=${TARGET_PORTS[*]}"
        echo "repos_detected=$(discover_repos | wc -l | tr -d ' ')"
    } >"$MANIFEST_FILE"
}

build_final_summary() {
    local started_epoch="$1"
    local finished_epoch="$2"

    local elapsed snapshots_count latest_snapshot dirty_repos failed_service_hits
    elapsed="$((finished_epoch - started_epoch))"
    snapshots_count="$(find "$SNAPSHOTS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    latest_snapshot="$(find "$SNAPSHOTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
    dirty_repos="$(awk -F'\t' 'NR > 1 && $3 + 0 > 0 {c++} END {print c+0}' "$latest_snapshot/repo-status.tsv" 2>/dev/null || echo "0")"
    failed_service_hits="$(rg -n "failed" "$latest_snapshot/systemd-user-services.txt" "$latest_snapshot/systemd-system-services.txt" 2>/dev/null | wc -l | tr -d ' ')"

    {
        echo "# GPT Overnight Run Summary"
        echo
        echo "- Run label: \`$RUN_LABEL\`"
        echo "- Started (UTC): \`$(date -u -d "@$started_epoch" +%Y-%m-%dT%H:%M:%SZ)\`"
        echo "- Finished (UTC): \`$(date -u -d "@$finished_epoch" +%Y-%m-%dT%H:%M:%SZ)\`"
        echo "- Elapsed seconds: \`$elapsed\`"
        echo "- Snapshot count: \`$snapshots_count\`"
        echo "- Latest snapshot: \`$(basename "$latest_snapshot")\`"
        echo
        echo "## Quick Signals"
        echo "- Dirty repositories in latest snapshot: \`$dirty_repos\`"
        echo "- \"failed\" service rows in latest systemctl outputs: \`$failed_service_hits\`"
        echo "- Artifacts root: \`$RUN_DIR\`"
        echo "- Recommendations: \`$RECOMMENDATIONS_FILE\`"
        echo
        echo "## Review Order"
        echo "1. \`$latest_snapshot/repo-status.tsv\`"
        echo "2. \`$latest_snapshot/athena-prd-lint.json\` and \`$latest_snapshot/athena-doc-gardener.json\`"
        echo "3. \`$latest_snapshot/systemd-targeted-user-services.txt\` and \`$latest_snapshot/ports-targeted.txt\`"
        echo "4. \`$RUN_LOG\`"
    } >"$SUMMARY_FILE"
}

write_manifest

START_EPOCH="$(date +%s)"
END_EPOCH="$((START_EPOCH + DURATION_SECONDS))"

log "Starting GPT overnight analysis run"
log "Run directory: $RUN_DIR"
log "Duration: ${DURATION_SECONDS}s | Interval: ${INTERVAL_SECONDS}s"

iteration=1
while true; do
    now_epoch="$(date +%s)"
    if (( now_epoch >= END_EPOCH )); then
        break
    fi

    label="$(printf "snapshot-%03d" "$iteration")"
    collect_snapshot "$label"

    now_epoch="$(date +%s)"
    remaining="$((END_EPOCH - now_epoch))"
    if (( remaining <= 0 )); then
        break
    fi
    sleep_seconds="$INTERVAL_SECONDS"
    if (( remaining < sleep_seconds )); then
        sleep_seconds="$remaining"
    fi
    log "Sleeping ${sleep_seconds}s before next snapshot"
    sleep "$sleep_seconds"
    iteration="$((iteration + 1))"
done

collect_snapshot "snapshot-final"
FINAL_EPOCH="$(date +%s)"

LATEST_SNAPSHOT="$(find "$SNAPSHOTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
build_recommendations "$LATEST_SNAPSHOT"
build_final_summary "$START_EPOCH" "$FINAL_EPOCH"

log "Run completed"
log "Summary: $SUMMARY_FILE"
log "Recommendations: $RECOMMENDATIONS_FILE"
