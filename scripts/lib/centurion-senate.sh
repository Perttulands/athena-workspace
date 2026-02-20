# shellcheck shell=bash
# centurion-senate.sh — Senate escalation helpers for Centurion
# Source this file; do not execute directly.

SENATE_ESCALATION_LAST_CASE_ID=""
SENATE_ESCALATION_LAST_FILE=""

senate_inbox_dir() {
    if [[ -n "${CENTURION_SENATE_INBOX_DIR:-}" ]]; then
        echo "$CENTURION_SENATE_INBOX_DIR"
        return 0
    fi
    echo "$WORKSPACE_ROOT/state/senate-inbox"
}

escalate_to_senate() {
    local repo_path="$1" branch="$2" reason="$3" quality_level="$4"
    local conflict_report_json="${5:-}"
    local auto_resolution_json="${6:-}"
    local inbox_dir case_id case_file tmp_file
    [[ -n "$conflict_report_json" ]] || conflict_report_json='{}'
    [[ -n "$auto_resolution_json" ]] || auto_resolution_json='{}'

    inbox_dir="$(senate_inbox_dir)"
    mkdir -p "$inbox_dir"

    case_id="centurion-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
    case_file="$inbox_dir/${case_id}.json"
    tmp_file="$(mktemp "$case_file.tmp.XXXXXX")"

    if ! jq -cn \
        --arg case_id "$case_id" \
        --arg source "centurion" \
        --arg repo "$repo_path" \
        --arg branch "$branch" \
        --arg reason "$reason" \
        --arg level "$quality_level" \
        --arg requested_at "$(iso_now)" \
        --argjson conflict_report "$conflict_report_json" \
        --argjson auto_resolution "$auto_resolution_json" \
        '{
            case_id:$case_id,
            source:$source,
            requested_at:$requested_at,
            reason:$reason,
            quality_level:$level,
            repo:$repo,
            branch:$branch,
            status:"pending",
            conflict_report:$conflict_report,
            auto_resolution:$auto_resolution
        }' > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$case_file"
    SENATE_ESCALATION_LAST_CASE_ID="$case_id"
    SENATE_ESCALATION_LAST_FILE="$case_file"

    printf '%s\n' "$case_file"
}
