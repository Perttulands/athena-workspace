# shellcheck shell=bash
# centurion-conflicts.sh — Conflict analysis helpers for Centurion
# Source this file; do not execute directly.

CONFLICT_REPORT_LAST_JSON='{"conflict_count":0,"conflicts":[]}'

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
