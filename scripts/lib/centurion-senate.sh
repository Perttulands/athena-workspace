# shellcheck shell=bash
# centurion-senate.sh — Senate escalation helpers for Centurion
# Source this file; do not execute directly.

SENATE_ESCALATION_LAST_CASE_ID=""
SENATE_ESCALATION_LAST_FILE=""
SENATE_RESOLUTION_LAST_JSON='{"status":"none"}'

senate_inbox_dir() {
    if [[ -n "${CENTURION_SENATE_INBOX_DIR:-}" ]]; then
        echo "$CENTURION_SENATE_INBOX_DIR"
        return 0
    fi
    echo "$WORKSPACE_ROOT/state/senate-inbox"
}

senate_verdicts_dir() {
    if [[ -n "${CENTURION_SENATE_VERDICTS_DIR:-}" ]]; then
        echo "$CENTURION_SENATE_VERDICTS_DIR"
        return 0
    fi
    echo "$WORKSPACE_ROOT/state/senate-verdicts"
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

    case_id="${CENTURION_SENATE_CASE_ID:-centurion-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM}"
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

senate_wait_for_verdict() {
    local case_id="$1"
    local wait_seconds="${2:-0}"
    local verdict_dir verdict_file deadline

    verdict_dir="$(senate_verdicts_dir)"
    verdict_file="$verdict_dir/${case_id}.json"
    mkdir -p "$verdict_dir"

    if [[ -f "$verdict_file" ]]; then
        printf '%s\n' "$verdict_file"
        return 0
    fi

    if ! is_integer "$wait_seconds"; then
        wait_seconds=0
    fi
    deadline=$(( $(date +%s) + wait_seconds ))
    while (( $(date +%s) <= deadline )); do
        [[ -f "$verdict_file" ]] && { printf '%s\n' "$verdict_file"; return 0; }
        sleep 1
    done

    return 1
}

apply_senate_verdict() {
    local repo_path="$1" verdict_file="$2"
    local mode files_json
    local resolved_json='[]'
    local unresolved_json='[]'
    local resolved_count=0 unresolved_count=0
    local -a conflicted_files=()

    [[ -f "$verdict_file" ]] || return 1
    mode="$(jq -r '.resolution.mode // .mode // "manual"' "$verdict_file" 2>/dev/null)" || mode="manual"
    files_json="$(jq -c '.resolution.files // .files // []' "$verdict_file" 2>/dev/null)" || files_json='[]'

    mapfile -t conflicted_files < <(git -C "$repo_path" diff --name-only --diff-filter=U 2>/dev/null || true)
    [[ ${#conflicted_files[@]} -gt 0 ]] || return 1

    for file in "${conflicted_files[@]}"; do
        [[ -n "$file" ]] || continue
        local strategy="$mode"
        local explicit
        explicit="$(jq -r --arg file "$file" '.[] | select(.path == $file) | .strategy' <<<"$files_json" 2>/dev/null | head -n1 || true)"
        [[ -n "$explicit" ]] && strategy="$explicit"

        if [[ "$strategy" == "ours" || "$strategy" == "theirs" ]]; then
            if git -C "$repo_path" checkout "--$strategy" -- "$file" >/dev/null 2>&1 && git -C "$repo_path" add -- "$file" >/dev/null 2>&1; then
                resolved_count=$((resolved_count + 1))
                resolved_json="$(jq -cn \
                    --argjson current "$resolved_json" \
                    --arg file "$file" \
                    --arg strategy "$strategy" \
                    '$current + [{file:$file, strategy:$strategy}]')"
            else
                unresolved_count=$((unresolved_count + 1))
                unresolved_json="$(jq -cn \
                    --argjson current "$unresolved_json" \
                    --arg file "$file" \
                    --arg reason "checkout_failed" \
                    '$current + [{file:$file, reason:$reason}]')"
            fi
        else
            unresolved_count=$((unresolved_count + 1))
            unresolved_json="$(jq -cn \
                --argjson current "$unresolved_json" \
                --arg file "$file" \
                --arg reason "manual_resolution_required" \
                '$current + [{file:$file, reason:$reason}]')"
        fi
    done

    SENATE_RESOLUTION_LAST_JSON="$(jq -cn \
        --arg status "applied" \
        --arg verdict_file "$verdict_file" \
        --arg mode "$mode" \
        --argjson resolved_count "$resolved_count" \
        --argjson unresolved_count "$unresolved_count" \
        --argjson resolved "$resolved_json" \
        --argjson unresolved "$unresolved_json" \
        '{status:$status, verdict_file:$verdict_file, mode:$mode, resolved_count:$resolved_count, unresolved_count:$unresolved_count, resolved:$resolved, unresolved:$unresolved}')"

    if (( unresolved_count == 0 && resolved_count > 0 )); then
        if git -C "$repo_path" commit --no-edit >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

resolve_conflict_via_senate() {
    local repo_path="$1" case_id="$2"
    local wait_seconds="${CENTURION_SENATE_WAIT_SECONDS:-0}"
    local verdict_file

    verdict_file="$(senate_wait_for_verdict "$case_id" "$wait_seconds")" || {
        SENATE_RESOLUTION_LAST_JSON='{"status":"pending"}'
        return 1
    }

    apply_senate_verdict "$repo_path" "$verdict_file"
}
