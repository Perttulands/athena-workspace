# shellcheck shell=bash
# record.sh — Run and result record building, validation, and writing
# Source this file; do not execute directly.
# Requires: common.sh sourced, and these globals set:
#   BEAD_ID, AGENT_TYPE, MODEL, REPO_PATH, PROMPT, PROMPT_TRUNCATED, PROMPT_HASH,
#   STARTED_AT, SESSION_NAME, RESULT_RECORD, RUN_RECORD, TEMPLATE_NAME,
#   ATTEMPT, MAX_RETRIES, RUNS_DIR, RESULTS_DIR, WORKSPACE_ROOT

validate_run_record_file() {
    local file="$1"
    jq -e '
        type == "object" and
        (.schema_version == 1) and
        (.bead | type == "string" and length > 0) and
        (.agent as $a | ["claude", "codex"] | index($a) != null) and
        (.model | type == "string" and length > 0) and
        (.repo | type == "string" and length > 0) and
        (.prompt | type == "string") and
        (.prompt_hash | type == "string" and test("^[a-f0-9]{64}$")) and
        (.started_at | type == "string") and
        ((.finished_at == null) or (.finished_at | type == "string")) and
        ((.duration_seconds == null) or (.duration_seconds | type == "number" and . >= 0 and floor == .)) and
        (.status as $s | ["running", "done", "failed", "timeout"] | index($s) != null) and
        (.attempt | type == "number" and . >= 1 and floor == .) and
        (.max_retries | type == "number" and . >= 1 and floor == .) and
        (.session_name | type == "string" and length > 0) and
        (.result_file | type == "string" and length > 0) and
        ((.exit_code == null) or (.exit_code | type == "number" and floor == .)) and
        ((.output_summary == null) or (.output_summary | type == "string")) and
        ((.failure_reason == null) or (.failure_reason | type == "string")) and
        ((.template_name == null) or (.template_name | type == "string")) and
        (.prompt_full | type == "string")
    ' "$file" >/dev/null
}

validate_result_record_file() {
    local file="$1"
    jq -e '
        type == "object" and
        (.schema_version == 1) and
        (.bead | type == "string" and length > 0) and
        (.agent as $a | ["claude", "codex"] | index($a) != null) and
        (.status as $s | ["running", "done", "failed", "timeout"] | index($s) != null) and
        (.reason | type == "string" and length > 0) and
        (.started_at | type == "string") and
        ((.finished_at == null) or (.finished_at | type == "string")) and
        ((.duration_seconds == null) or (.duration_seconds | type == "number" and . >= 0 and floor == .)) and
        (.attempt | type == "number" and . >= 1 and floor == .) and
        (.max_retries | type == "number" and . >= 1 and floor == .) and
        (.will_retry | type == "boolean") and
        ((.exit_code == null) or (.exit_code | type == "number" and floor == .)) and
        (.session_name | type == "string" and length > 0) and
        ((.output_summary == null) or (.output_summary | type == "string"))
    ' "$file" >/dev/null
}

atomic_write_json() {
    local target="$1"
    local payload="$2"
    local validator="$3"
    local tmp
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    printf '%s\n' "$payload" > "$tmp"

    if ! jq -e . "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "Error: generated invalid JSON for $target" >&2
        exit 1
    fi

    if ! "$validator" "$tmp"; then
        rm -f "$tmp"
        echo "Error: JSON schema validation failed for $target" >&2
        exit 1
    fi

    mv "$tmp" "$target"
}

build_run_payload() {
    local status="$1"
    local finished_at="$2"
    local duration="$3"
    local exit_code="$4"
    local output_summary="${5:-}"
    local failure_reason="${6:-}"
    local verification="${7:-null}"

    jq -cn \
        --arg bead "$BEAD_ID" \
        --arg agent "$AGENT_TYPE" \
        --arg model "$MODEL" \
        --arg repo "$REPO_PATH" \
        --arg prompt "$PROMPT_TRUNCATED" \
        --arg prompt_hash "$PROMPT_HASH" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$finished_at" \
        --arg duration "$duration" \
        --arg status "$status" \
        --arg exit_code "$exit_code" \
        --arg session_name "$SESSION_NAME" \
        --arg result_file "$RESULT_RECORD" \
        --arg output_summary "$output_summary" \
        --arg failure_reason "$failure_reason" \
        --arg template_name "$TEMPLATE_NAME" \
        --arg prompt_full "$PROMPT" \
        --argjson attempt "$ATTEMPT" \
        --argjson max_retries "$MAX_RETRIES" \
        --argjson verification "$verification" \
        '{
            schema_version: 1,
            bead: $bead,
            agent: $agent,
            model: $model,
            repo: $repo,
            prompt: $prompt,
            prompt_hash: $prompt_hash,
            started_at: $started_at,
            finished_at: (if $finished_at == "" then null else $finished_at end),
            duration_seconds: (if $duration == "" then null else ($duration | tonumber) end),
            status: $status,
            attempt: $attempt,
            max_retries: $max_retries,
            session_name: $session_name,
            result_file: $result_file,
            exit_code: (if $exit_code == "" then null else ($exit_code | tonumber) end),
            output_summary: (if $output_summary == "" then null else $output_summary end),
            failure_reason: (if $failure_reason == "" then null else $failure_reason end),
            template_name: (if $template_name == "" then null else $template_name end),
            prompt_full: $prompt_full,
            verification: $verification
        }'
}

write_run_record() {
    local status="$1"
    local finished_at="$2"
    local duration="$3"
    local exit_code="$4"
    local output_summary="${5:-}"
    local failure_reason="${6:-}"
    local verification="${7:-null}"
    local payload

    payload="$(build_run_payload "$status" "$finished_at" "$duration" "$exit_code" "$output_summary" "$failure_reason" "$verification")"
    atomic_write_json "$RUN_RECORD" "$payload" validate_run_record_file
}

build_result_payload() {
    local status="$1"
    local reason="$2"
    local finished_at="$3"
    local duration="$4"
    local exit_code="$5"
    local will_retry="$6"
    local output_summary="${7:-}"
    local verification="${8:-null}"

    jq -cn \
        --arg bead "$BEAD_ID" \
        --arg agent "$AGENT_TYPE" \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$finished_at" \
        --arg duration "$duration" \
        --arg exit_code "$exit_code" \
        --arg session_name "$SESSION_NAME" \
        --arg output_summary "$output_summary" \
        --argjson attempt "$ATTEMPT" \
        --argjson max_retries "$MAX_RETRIES" \
        --argjson will_retry "$will_retry" \
        --argjson verification "$verification" \
        '{
            schema_version: 1,
            bead: $bead,
            agent: $agent,
            status: $status,
            reason: $reason,
            started_at: $started_at,
            finished_at: (if $finished_at == "" then null else $finished_at end),
            duration_seconds: (if $duration == "" then null else ($duration | tonumber) end),
            attempt: $attempt,
            max_retries: $max_retries,
            will_retry: $will_retry,
            exit_code: (if $exit_code == "" then null else ($exit_code | tonumber) end),
            session_name: $session_name,
            output_summary: (if $output_summary == "" then null else $output_summary end),
            verification: $verification
        }'
}

write_result_record() {
    local status="$1"
    local reason="$2"
    local finished_at="$3"
    local duration="$4"
    local exit_code="$5"
    local will_retry="$6"
    local output_summary="${7:-}"
    local verification="${8:-null}"
    local payload

    payload="$(build_result_payload "$status" "$reason" "$finished_at" "$duration" "$exit_code" "$will_retry" "$output_summary" "$verification")"
    atomic_write_json "$RESULT_RECORD" "$payload" validate_result_record_file
}
