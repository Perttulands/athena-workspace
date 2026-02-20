# shellcheck shell=bash
# centurion-semantic.sh — Semantic review helpers for Centurion
# Source this file; do not execute directly.

SEMANTIC_REVIEW_LAST_JSON=""
SEMANTIC_REVIEW_LAST_VERDICT="review-needed"
SEMANTIC_REVIEW_LAST_SUMMARY="semantic review not run"
SEMANTIC_REVIEW_LAST_OUTPUT=""
SEMANTIC_REVIEW_LAST_FLAGS="[]"
SEMANTIC_GAMING_FLAGS_JSON="[]"
SEMANTIC_GAMING_SEVERITY="none"
SEMANTIC_GAMING_SUMMARY=""

semantic_review_prompt_file() {
    if [[ -n "${CENTURION_SEMANTIC_PROMPT_FILE:-}" ]]; then
        echo "$CENTURION_SEMANTIC_PROMPT_FILE"
        return 0
    fi
    echo "$WORKSPACE_ROOT/skills/centurion-review.md"
}

semantic_review_model() {
    if [[ -n "${CENTURION_SEMANTIC_MODEL:-}" ]]; then
        echo "$CENTURION_SEMANTIC_MODEL"
        return 0
    fi

    if [[ -f "${CONFIG_FILE:-}" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.claude.default_model // "opus"' "$CONFIG_FILE"
        return 0
    fi

    echo "opus"
}

semantic_extract_diff() {
    local repo_path="$1" target_branch="$2" source_branch="$3"
    git -C "$repo_path" diff --no-color --unified=3 "${target_branch}...${source_branch}" 2>/dev/null || true
}

semantic_extract_changed_files() {
    local repo_path="$1" target_branch="$2" source_branch="$3"
    git -C "$repo_path" diff --name-only "${target_branch}...${source_branch}" 2>/dev/null || true
}

semantic_is_test_file() {
    local file="$1"
    [[ "$file" =~ (^|/)(test|tests)/ ]] || [[ "$file" =~ (_test\.[^/]+$|\.test\.[^/]+$|\.spec\.[^/]+$) ]]
}

semantic_detect_test_gaming() {
    local repo_path="$1" target_branch="$2" source_branch="$3"
    local has_source_changes=0 has_test_changes=0 removed_assertions=0 added_skip_markers=0
    local severity="none"
    local summary="no suspicious test-gaming patterns detected"
    local -a changed_files=()
    local -a flags=()

    mapfile -t changed_files < <(semantic_extract_changed_files "$repo_path" "$target_branch" "$source_branch")
    for file in "${changed_files[@]}"; do
        [[ -n "$file" ]] || continue

        if semantic_is_test_file "$file"; then
            has_test_changes=1
            local test_diff
            test_diff="$(git -C "$repo_path" diff --no-color "${target_branch}...${source_branch}" -- "$file" 2>/dev/null || true)"
            local removed_assertions_here=0
            local added_assertions_here=0
            if printf '%s\n' "$test_diff" | grep -E '^-.*(assert|expect\(|require\.|t\.(Fatal|Error|Fail(Now)?))' >/dev/null; then
                removed_assertions_here=1
            fi
            if printf '%s\n' "$test_diff" | grep -E '^\+.*(assert|expect\(|require\.|t\.(Fatal|Error|Fail(Now)?))' >/dev/null; then
                added_assertions_here=1
            fi
            if (( removed_assertions_here == 1 && added_assertions_here == 0 )); then
                removed_assertions=1
            fi
            if printf '%s\n' "$test_diff" | grep -E '^\+.*(\.skip\(|t\.Skip\(|xit\(|xdescribe\(|@Disabled)' >/dev/null; then
                added_skip_markers=1
            fi
        else
            has_source_changes=1
        fi
    done

    if (( removed_assertions == 1 )); then
        flags+=("test.assertions_removed")
        severity="high"
    fi
    if (( added_skip_markers == 1 )); then
        flags+=("test.skip_added")
        severity="high"
    fi
    if (( has_source_changes == 1 && has_test_changes == 0 )); then
        flags+=("test.coverage_gap")
        if [[ "$severity" != "high" ]]; then
            severity="medium"
        fi
    fi

    if [[ ${#flags[@]} -gt 0 ]]; then
        summary="suspicious patterns: $(IFS=', '; echo "${flags[*]}")"
    fi

    SEMANTIC_GAMING_FLAGS_JSON="$(jq -cn '$ARGS.positional' --args "${flags[@]}")"
    SEMANTIC_GAMING_SEVERITY="$severity"
    SEMANTIC_GAMING_SUMMARY="$summary"
}

semantic_build_prompt() {
    local repo_path="$1" target_branch="$2" source_branch="$3"
    local prompt_file
    local changed_files
    local diff_text

    prompt_file="$(semantic_review_prompt_file)"
    changed_files="$(semantic_extract_changed_files "$repo_path" "$target_branch" "$source_branch")"
    diff_text="$(semantic_extract_diff "$repo_path" "$target_branch" "$source_branch")"

    if [[ -f "$prompt_file" ]]; then
        {
            cat "$prompt_file"
            echo
            echo "## Review Context"
            echo "- Repository: $repo_path"
            echo "- Target branch: $target_branch"
            echo "- Source branch: $source_branch"
            echo "- Changed files:"
            if [[ -n "$changed_files" ]]; then
                printf '%s\n' "$changed_files" | sed 's/^/- /'
            else
                echo "- (none)"
            fi
            echo "- Test-gaming pre-check severity: ${SEMANTIC_GAMING_SEVERITY:-none}"
            echo "- Test-gaming pre-check summary: ${SEMANTIC_GAMING_SUMMARY:-n/a}"
            if [[ "${SEMANTIC_GAMING_FLAGS_JSON:-[]}" != "[]" ]]; then
                echo "- Test-gaming flags:"
                jq -r '.[]' <<<"${SEMANTIC_GAMING_FLAGS_JSON:-[]}" | sed 's/^/  - /'
            fi
            echo
            echo "## Diff"
            if [[ -n "$diff_text" ]]; then
                printf '%s\n' "$diff_text"
            else
                echo "(empty diff)"
            fi
            echo
            echo "Return only JSON."
        }
        return 0
    fi

    cat <<PROMPT
You are a semantic code reviewer for merge safety.

Return JSON only with keys:
- verdict: pass | fail | review-needed
- summary: short sentence
- flags: array of strings

Repo: $repo_path
Target: $target_branch
Source: $source_branch
Changed files:
${changed_files:-none}

Diff:
${diff_text:-empty}
PROMPT
}

semantic_set_result() {
    local verdict="$1" summary="$2" flags_json="$3" raw_output="$4"
    local ts
    ts="$(iso_now)"

    SEMANTIC_REVIEW_LAST_VERDICT="$verdict"
    SEMANTIC_REVIEW_LAST_SUMMARY="$summary"
    SEMANTIC_REVIEW_LAST_FLAGS="$flags_json"
    SEMANTIC_REVIEW_LAST_OUTPUT="$raw_output"
    SEMANTIC_REVIEW_LAST_JSON="$(jq -cn \
        --arg verdict "$verdict" \
        --arg summary "$summary" \
        --arg raw "$raw_output" \
        --arg ts "$ts" \
        --argjson flags "$flags_json" \
        '{verdict:$verdict, summary:$summary, flags:$flags, raw_output:$raw, reviewed_at:$ts}')"
}

semantic_parse_review_json() {
    local raw="$1"
    local json_line=""

    if printf '%s' "$raw" | jq empty >/dev/null 2>&1; then
        json_line="$raw"
    else
        json_line="$(printf '%s\n' "$raw" | sed -n '/{/,/}/p' | head -1)"
    fi

    if [[ -z "$json_line" ]] || ! printf '%s' "$json_line" | jq empty >/dev/null 2>&1; then
        semantic_set_result "review-needed" "semantic review output was not valid JSON" '[]' "$raw"
        return 2
    fi

    local verdict summary flags_json
    verdict="$(printf '%s' "$json_line" | jq -r '.verdict // "review-needed"')"
    summary="$(printf '%s' "$json_line" | jq -r '.summary // "semantic review completed"')"
    flags_json="$(printf '%s' "$json_line" | jq -c '.flags // []')"

    case "$verdict" in
        pass)
            semantic_set_result "pass" "$summary" "$flags_json" "$raw"
            return 0
            ;;
        fail)
            semantic_set_result "fail" "$summary" "$flags_json" "$raw"
            return 1
            ;;
        review-needed)
            semantic_set_result "review-needed" "$summary" "$flags_json" "$raw"
            return 2
            ;;
        *)
            semantic_set_result "review-needed" "semantic review returned unknown verdict: $verdict" "$flags_json" "$raw"
            return 2
            ;;
    esac
}

run_semantic_review() {
    local repo_path="$1" source_branch="$2" target_branch="${3:-main}"
    local prompt review_cmd model output
    local parse_rc=0
    local merged_flags="[]"

    semantic_detect_test_gaming "$repo_path" "$target_branch" "$source_branch"
    if [[ "$SEMANTIC_GAMING_SEVERITY" == "high" ]]; then
        semantic_set_result "fail" "semantic review rejected potential test gaming: $SEMANTIC_GAMING_SUMMARY" "$SEMANTIC_GAMING_FLAGS_JSON" ""
        return 1
    fi

    prompt="$(semantic_build_prompt "$repo_path" "$target_branch" "$source_branch")"

    if [[ -n "${CENTURION_SEMANTIC_REVIEW_CMD:-}" ]]; then
        review_cmd="$CENTURION_SEMANTIC_REVIEW_CMD"
    else
        if ! command -v claude >/dev/null 2>&1; then
            semantic_set_result "review-needed" "claude CLI unavailable for semantic review" '[]' ""
            return 2
        fi
        model="$(semantic_review_model)"
        review_cmd="claude -p --dangerously-skip-permissions --model $model"
    fi

    if ! output="$(printf '%s\n' "$prompt" | bash -lc "$review_cmd" 2>&1)"; then
        semantic_set_result "review-needed" "semantic review command failed" '[]' "$output"
        return 2
    fi

    if semantic_parse_review_json "$output"; then
        parse_rc=0
    else
        parse_rc=$?
    fi

    if [[ "${SEMANTIC_GAMING_FLAGS_JSON:-[]}" != "[]" ]]; then
        merged_flags="$(jq -cn --argjson review "${SEMANTIC_REVIEW_LAST_FLAGS:-[]}" --argjson gaming "${SEMANTIC_GAMING_FLAGS_JSON:-[]}" \
            '$review + $gaming | unique')"
        if [[ "$SEMANTIC_GAMING_SEVERITY" == "medium" && "$SEMANTIC_REVIEW_LAST_VERDICT" == "pass" ]]; then
            semantic_set_result "review-needed" "semantic review flagged potential test gaming: $SEMANTIC_GAMING_SUMMARY" "$merged_flags" "$output"
            return 2
        fi
        semantic_set_result "$SEMANTIC_REVIEW_LAST_VERDICT" "$SEMANTIC_REVIEW_LAST_SUMMARY" "$merged_flags" "$output"
        return "$parse_rc"
    fi

    return "$parse_rc"
}
