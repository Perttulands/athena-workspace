#!/usr/bin/env bash
# prd-lint.sh - Enforce canonical feature PRD governance

set -euo pipefail

if [[ -v WORKSPACE_ROOT ]]; then
    WORKSPACE_ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT cannot be empty}"
else
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
FEATURES_DIR="$WORKSPACE_ROOT/docs/features"

usage() {
    cat <<EOF
Usage: prd-lint.sh [OPTIONS]

Validate feature PRD governance:
  - canonical location docs/features/<slug>/PRD.md
  - one PRD per feature
  - required metadata header
  - required product sections (overview/objectives, personas/stories, scope, DoD)
  - reject implementation-checklist style PRDs in canonical docs
  - staleness check: last_updated vs scope_paths commit dates

OPTIONS:
  --help        Show this help message
  --json        Output JSON report
  --features-dir DIR  Override feature PRD directory

EXIT CODES:
  0  No issues found
  1  Issues found
EOF
}

JSON_OUTPUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --features-dir)
            FEATURES_DIR="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

declare -a issues=()

add_issue() {
    local feature="$1"
    local doc="$2"
    local issue_type="$3"
    local detail="$4"
    local fix="$5"
    issues+=("{\"feature\":\"$feature\",\"doc\":\"$doc\",\"type\":\"$issue_type\",\"detail\":\"$detail\",\"suggested_fix\":\"$fix\"}")
}

trim_quotes() {
    local s="$1"
    s="${s%\"}"
    s="${s#\"}"
    s="${s%\'}"
    s="${s#\'}"
    printf '%s' "$s"
}

get_scalar() {
    local key="$1"
    local frontmatter="$2"
    printf '%s\n' "$frontmatter" | sed -n "s/^${key}:[[:space:]]*//p" | head -n 1
}

extract_scope_paths() {
    local frontmatter="$1"
    printf '%s\n' "$frontmatter" | awk '
        BEGIN { in_scope=0 }
        /^scope_paths:[[:space:]]*$/ { in_scope=1; next }
        in_scope && /^  - / { sub(/^  - /, "", $0); print; next }
        in_scope && !/^  - / { in_scope=0 }
    '
}

extract_prd_body() {
    local file="$1"
    awk '
        BEGIN { fm=0 }
        NR==1 && /^---$/ { fm=1; next }
        fm==1 && /^---$/ { fm=2; next }
        fm==2 { print }
    ' "$file"
}

has_h2() {
    local body="$1"
    local heading_regex="$2"
    printf '%s\n' "$body" | grep -Eqi "^##[[:space:]]+${heading_regex}[[:space:]]*$"
}

validate_feature_prd() {
    local feature_dir="$1"
    local feature_slug
    feature_slug="$(basename "$feature_dir")"

    local canonical="$feature_dir/PRD.md"

    mapfile -t prd_files < <(find "$feature_dir" -maxdepth 1 -type f -name 'PRD*.md' | sort)
    local prd_count="${#prd_files[@]}"

    if (( prd_count == 0 )); then
        add_issue "$feature_slug" "$feature_dir" "missing-prd" \
            "feature directory has no PRD*.md file" \
            "Add canonical PRD at docs/features/$feature_slug/PRD.md"
        return
    fi

    if (( prd_count > 1 )); then
        add_issue "$feature_slug" "$feature_dir" "multiple-prds" \
            "feature directory contains $prd_count PRD*.md files" \
            "Keep exactly one canonical PRD.md file"
    fi

    if [[ ! -f "$canonical" ]]; then
        add_issue "$feature_slug" "$feature_dir" "non-canonical-location" \
            "canonical PRD.md is missing" \
            "Rename primary PRD file to PRD.md"
        return
    fi

    if [[ "$(head -n 1 "$canonical" 2>/dev/null || true)" != "---" ]]; then
        add_issue "$feature_slug" "$canonical" "missing-header" \
            "PRD is missing required metadata header block" \
            "Add YAML-style metadata header at top of PRD"
        return
    fi

    local frontmatter
    frontmatter="$(awk '
        NR==1 { next }
        /^---$/ { exit }
        { print }
    ' "$canonical")"

    if [[ -z "$frontmatter" ]]; then
        add_issue "$feature_slug" "$canonical" "empty-header" \
            "metadata header is empty" \
            "Populate required metadata keys"
        return
    fi

    local header_slug header_bead header_status header_owner header_last_updated header_source
    header_slug="$(trim_quotes "$(get_scalar "feature_slug" "$frontmatter")")"
    header_bead="$(trim_quotes "$(get_scalar "primary_bead" "$frontmatter")")"
    header_status="$(trim_quotes "$(get_scalar "status" "$frontmatter")")"
    header_owner="$(trim_quotes "$(get_scalar "owner" "$frontmatter")")"
    header_last_updated="$(trim_quotes "$(get_scalar "last_updated" "$frontmatter")")"
    header_source="$(trim_quotes "$(get_scalar "source_of_truth" "$frontmatter")")"
    local prd_body
    prd_body="$(extract_prd_body "$canonical")"

    local -a required_keys=("feature_slug" "primary_bead" "status" "owner" "scope_paths" "last_updated" "source_of_truth")
    local key
    for key in "${required_keys[@]}"; do
        if ! printf '%s\n' "$frontmatter" | grep -q "^${key}:"; then
            add_issue "$feature_slug" "$canonical" "missing-key" \
                "missing required metadata key: $key" \
                "Add metadata key '$key' to PRD header"
        fi
    done

    if [[ -n "$header_slug" && "$header_slug" != "$feature_slug" ]]; then
        add_issue "$feature_slug" "$canonical" "slug-mismatch" \
            "feature_slug '$header_slug' does not match directory '$feature_slug'" \
            "Set feature_slug to '$feature_slug'"
    fi

    if [[ -n "$header_bead" ]] && [[ ! "$header_bead" =~ ^bd-[a-z0-9][a-z0-9-]*$ ]]; then
        add_issue "$feature_slug" "$canonical" "invalid-primary-bead" \
            "primary_bead '$header_bead' is not a valid bd-* id" \
            "Use a valid bead id like bd-123 or bd-abc"
    fi

    if [[ -n "$header_source" && "$header_source" != "true" ]]; then
        add_issue "$feature_slug" "$canonical" "not-source-of-truth" \
            "source_of_truth must be true for canonical PRD" \
            "Set source_of_truth: true"
    fi

    if [[ -z "$header_owner" ]]; then
        add_issue "$feature_slug" "$canonical" "missing-owner" \
            "owner is empty" \
            "Set owner to responsible maintainer"
    fi

    if [[ -n "$header_status" ]] && [[ ! "$header_status" =~ ^(draft|active|complete|archived|deprecated)$ ]]; then
        add_issue "$feature_slug" "$canonical" "invalid-status" \
            "status '$header_status' is not in {draft,active,complete,archived,deprecated}" \
            "Use one allowed status value"
    fi

    # Canonical PRD content checks (product requirements, not execution checklist)
    if ! has_h2 "$prd_body" "(Overview[[:space:]]*&[[:space:]]*Objectives|Overview and Objectives)"; then
        add_issue "$feature_slug" "$canonical" "missing-overview-objectives" \
            "missing required section: Overview & Objectives" \
            "Add an H2 section named 'Overview & Objectives'"
    fi

    if ! has_h2 "$prd_body" "Target Personas[[:space:]]*&[[:space:]]*User Stories"; then
        add_issue "$feature_slug" "$canonical" "missing-personas-stories" \
            "missing required section: Target Personas & User Stories" \
            "Add personas and user stories in that section"
    fi

    if ! has_h2 "$prd_body" "(Functional Requirements[[:space:]]*&[[:space:]]*Scope|Functional Requirements/Scope)"; then
        add_issue "$feature_slug" "$canonical" "missing-functional-scope" \
            "missing required section: Functional Requirements & Scope" \
            "Add prioritized must/should/won't scope"
    fi

    if ! has_h2 "$prd_body" "Definition of Done"; then
        add_issue "$feature_slug" "$canonical" "missing-definition-of-done" \
            "missing required section: Definition of Done" \
            "Add explicit done/working criteria"
    fi

    if ! printf '%s\n' "$prd_body" | grep -Eq 'As a [^,]+, I want to [^,]+ so that [^.]+'; then
        add_issue "$feature_slug" "$canonical" "missing-user-story-format" \
            "no user stories found in 'As a ..., I want to ... so that ...' format" \
            "Add at least one user story in that format"
    fi

    if printf '%s\n' "$prd_body" | grep -Eq '^##[[:space:]]+Sprint[[:space:]]'; then
        add_issue "$feature_slug" "$canonical" "implementation-plan-mixed" \
            "canonical PRD contains sprint execution sections" \
            "Move sprint/task sequencing to docs/specs/ and keep PRD product-focused"
    fi

    if printf '%s\n' "$prd_body" | grep -Eq '\*\*US-[0-9A-Za-z-]+'; then
        add_issue "$feature_slug" "$canonical" "implementation-plan-mixed" \
            "canonical PRD contains US-* implementation checklist content" \
            "Move implementation checklist to docs/specs/ and keep PRD user/outcome focused"
    fi

    if [[ -z "$header_last_updated" ]]; then
        add_issue "$feature_slug" "$canonical" "missing-last-updated" \
            "last_updated is empty" \
            "Set last_updated in YYYY-MM-DD format"
    else
        if ! parsed_date="$(date -u -d "$header_last_updated" +%Y-%m-%d 2>/dev/null)"; then
            add_issue "$feature_slug" "$canonical" "invalid-last-updated" \
                "last_updated '$header_last_updated' is not parseable as a date" \
                "Use YYYY-MM-DD format"
        else
            local today
            today="$(date -u +%Y-%m-%d)"
            if [[ "$parsed_date" > "$today" ]]; then
                add_issue "$feature_slug" "$canonical" "future-last-updated" \
                    "last_updated '$parsed_date' is in the future" \
                    "Use current or past date"
            fi
        fi
    fi

    mapfile -t scopes < <(extract_scope_paths "$frontmatter")
    if (( ${#scopes[@]} == 0 )); then
        add_issue "$feature_slug" "$canonical" "missing-scope-paths" \
            "scope_paths list is empty" \
            "Add at least one path that defines PRD scope"
        return
    fi

    local scope
    for scope in "${scopes[@]}"; do
        scope="$(trim_quotes "$scope")"
        [[ -n "$scope" ]] || continue

        local has_match=0
        local latest_commit=""

        if [[ "$scope" == *"*"* || "$scope" == *"?"* || "$scope" == *"["* ]]; then
            mapfile -t matches < <(cd "$WORKSPACE_ROOT" && compgen -G "$scope" || true)
            if (( ${#matches[@]} == 0 )); then
                add_issue "$feature_slug" "$canonical" "scope-missing" \
                    "scope path pattern '$scope' has no matches" \
                    "Fix scope_paths to existing files/directories"
                continue
            fi
            has_match=1
            local match
            for match in "${matches[@]}"; do
                local m_latest
                m_latest="$(git -C "$WORKSPACE_ROOT" log -1 --format='%cs' -- "$match" 2>/dev/null || true)"
                if [[ -n "$m_latest" ]] && [[ -z "$latest_commit" || "$m_latest" > "$latest_commit" ]]; then
                    latest_commit="$m_latest"
                fi
            done
        else
            if [[ ! -e "$WORKSPACE_ROOT/$scope" ]]; then
                add_issue "$feature_slug" "$canonical" "scope-missing" \
                    "scope path '$scope' does not exist" \
                    "Fix scope_paths to existing files/directories"
                continue
            fi
            has_match=1
            latest_commit="$(git -C "$WORKSPACE_ROOT" log -1 --format='%cs' -- "$scope" 2>/dev/null || true)"
        fi

        if (( has_match == 1 )) && [[ -n "$header_last_updated" ]] && [[ "$header_last_updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ -n "$latest_commit" ]]; then
            if [[ "$latest_commit" > "$header_last_updated" ]]; then
                add_issue "$feature_slug" "$canonical" "stale-prd" \
                    "scope '$scope' changed on $latest_commit after last_updated $header_last_updated" \
                    "Review PRD and bump last_updated"
            fi
        fi
    done
}

if [[ ! -d "$FEATURES_DIR" ]]; then
    add_issue "global" "$FEATURES_DIR" "missing-features-dir" \
        "features directory does not exist" \
        "Create docs/features and canonical PRDs"
else
    declare -A seen_slugs=()
    mapfile -t feature_dirs < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

    if (( ${#feature_dirs[@]} == 0 )); then
        add_issue "global" "$FEATURES_DIR" "no-features" \
            "no feature directories found under docs/features" \
            "Create docs/features/<feature-slug>/PRD.md entries"
    fi

    for feature_dir in "${feature_dirs[@]}"; do
        feature_slug="$(basename "$feature_dir")"
        if [[ -n "${seen_slugs[$feature_slug]:-}" ]]; then
            add_issue "$feature_slug" "$feature_dir" "duplicate-feature-dir" \
                "duplicate feature slug directory found" \
                "Keep a single directory per feature slug"
            continue
        fi
        seen_slugs["$feature_slug"]=1
        validate_feature_prd "$feature_dir"
    done
fi

total_features=0
if [[ -d "$FEATURES_DIR" ]]; then
    total_features="$(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | awk '{print $1}')"
fi

total_issues="${#issues[@]}"
features_with_issues=0
if (( total_issues > 0 )); then
    features_with_issues="$(printf '%s\n' "${issues[@]}" | jq -r '.feature' | sort -u | wc -l || echo 0)"
fi

scanned_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if (( JSON_OUTPUT == 1 )); then
    issues_json="$(printf '%s\n' "${issues[@]}" | jq -s '.')"
    jq -n \
        --arg scanned_at "$scanned_at" \
        --arg features_dir "$FEATURES_DIR" \
        --argjson total_features "$total_features" \
        --argjson total_issues "$total_issues" \
        --argjson features_with_issues "$features_with_issues" \
        --argjson issues "$issues_json" \
        '{
            scanned_at: $scanned_at,
            features_dir: $features_dir,
            issues: $issues,
            summary: {
                total_features: $total_features,
                features_with_issues: $features_with_issues,
                total_issues: $total_issues
            }
        }'
else
    echo "PRD Lint Report"
    echo "==============="
    echo "Scanned: $total_features feature PRDs at $scanned_at"
    echo ""
    if (( total_issues == 0 )); then
        echo "PASS: No PRD governance issues found."
    else
        echo "FAIL: Found $total_issues issues across $features_with_issues features."
        echo ""
        for feature in $(printf '%s\n' "${issues[@]}" | jq -r '.feature' | sort -u); do
            echo "[$feature]"
            printf '%s\n' "${issues[@]}" | jq -r "select(.feature == \"$feature\") | \"  - [\(.type)] \(.detail)\""
            echo ""
        done
    fi
fi

if (( total_issues == 0 )); then
    exit 0
fi
exit 1
