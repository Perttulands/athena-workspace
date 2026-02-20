# shellcheck shell=bash
# centurion-conflicts.sh — Conflict analysis helpers for Centurion
# Source this file; do not execute directly.

CONFLICT_REPORT_LAST_JSON='{"conflict_count":0,"conflicts":[]}'
AUTO_RESOLUTION_LAST_JSON='{"resolved_count":0,"unresolved_count":0,"resolved":[],"unresolved":[]}'

collect_conflict_report() {
    local repo_path="$1"
    local conflicts_json='[]'
    local -a conflicted_files=()

    mapfile -t conflicted_files < <(git -C "$repo_path" diff --name-only --diff-filter=U 2>/dev/null || true)
    for file in "${conflicted_files[@]}"; do
        [[ -n "$file" ]] || continue

        local abs_file="$repo_path/$file"
        local preview=""
        local first_line=0 start_line=1 end_line=1
        local marker_lines_json='[]'
        local -a marker_lines=()

        if [[ -f "$abs_file" ]]; then
            mapfile -t marker_lines < <(grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$abs_file" | cut -d: -f1)
            if [[ ${#marker_lines[@]} -gt 0 ]]; then
                first_line="${marker_lines[0]}"
                start_line=$(( first_line > 2 ? first_line - 2 : 1 ))
                end_line=$(( first_line + 8 ))
                preview="$(sed -n "${start_line},${end_line}p" "$abs_file" | sed 's/[[:cntrl:]]\[[0-9;]*[mK]//g' | head -n 20)"
                marker_lines_json="$(jq -cn '$ARGS.positional | map(tonumber)' --args "${marker_lines[@]}")"
            fi
        fi

        conflicts_json="$(jq -cn \
            --argjson current "$conflicts_json" \
            --arg file "$file" \
            --arg preview "$preview" \
            --argjson marker_lines "$marker_lines_json" \
            '$current + [{file:$file, marker_lines:$marker_lines, preview:$preview}]')"
    done

    CONFLICT_REPORT_LAST_JSON="$(jq -cn --argjson conflicts "$conflicts_json" '{conflict_count: ($conflicts | length), conflicts:$conflicts}')"
    printf '%s\n' "$CONFLICT_REPORT_LAST_JSON"
}

auto_resolve_trivial_conflicts() {
    local repo_path="$1"
    local resolved_json='[]'
    local unresolved_json='[]'
    local resolved_count=0 unresolved_count=0
    local -a conflicted_files=()

    mapfile -t conflicted_files < <(git -C "$repo_path" diff --name-only --diff-filter=U 2>/dev/null || true)
    [[ ${#conflicted_files[@]} -gt 0 ]] || {
        AUTO_RESOLUTION_LAST_JSON='{"resolved_count":0,"unresolved_count":0,"resolved":[],"unresolved":[]}'
        return 1
    }

    for file in "${conflicted_files[@]}"; do
        [[ -n "$file" ]] || continue

        local ours_hash="" theirs_hash="" base_hash="" strategy=""
        while read -r _mode hash stage _path; do
            case "$stage" in
                1) base_hash="$hash" ;;
                2) ours_hash="$hash" ;;
                3) theirs_hash="$hash" ;;
            esac
        done < <(git -C "$repo_path" ls-files -u -- "$file" 2>/dev/null || true)

        if [[ -z "$ours_hash" && -n "$theirs_hash" ]]; then
            strategy="theirs"
        elif [[ -z "$theirs_hash" && -n "$ours_hash" ]]; then
            strategy="ours"
        elif [[ -n "$base_hash" && "$ours_hash" == "$base_hash" && "$theirs_hash" != "$base_hash" ]]; then
            strategy="theirs"
        elif [[ -n "$base_hash" && "$theirs_hash" == "$base_hash" && "$ours_hash" != "$base_hash" ]]; then
            strategy="ours"
        fi

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
                --arg reason "no_trivial_strategy" \
                '$current + [{file:$file, reason:$reason}]')"
        fi
    done

    AUTO_RESOLUTION_LAST_JSON="$(jq -cn \
        --argjson resolved_count "$resolved_count" \
        --argjson unresolved_count "$unresolved_count" \
        --argjson resolved "$resolved_json" \
        --argjson unresolved "$unresolved_json" \
        '{resolved_count:$resolved_count, unresolved_count:$unresolved_count, resolved:$resolved, unresolved:$unresolved}')"

    if (( unresolved_count == 0 && resolved_count > 0 )); then
        if git -C "$repo_path" commit --no-edit >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}
