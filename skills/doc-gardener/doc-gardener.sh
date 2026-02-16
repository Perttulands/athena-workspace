#!/usr/bin/env bash
# Documentation Gardener - Systematic documentation quality auditor
# Reviews README, SKILL.md, inline comments, JSDoc, and API docs

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ATHENA_WEB_DIR="$HOME/athena-web"
AUDITS_DIR="$WORKSPACE_DIR/state/doc-audits"
TEMPLATES_DIR="$WORKSPACE_DIR/templates"
CALIBRATION_FILE="$WORKSPACE_DIR/state/calibration/doc-gardener.jsonl"

# Command-line options
TARGET_PATH=""
DOC_TYPES=()
FOCUS_AREAS=()
OUTPUT_FORMAT="human"
MODEL="sonnet"
AUDIT_MODE="full"

# Valid options
VALID_DOC_TYPES=("readme" "skills" "jsdoc" "inline-comments" "api-docs" "all")
VALID_FOCUS=("clarity" "completeness" "examples" "consistency" "technical-accuracy" "all")
VALID_FORMATS=("human" "json")

usage() {
    cat << EOF
Documentation Gardener - Systematic documentation quality auditor

Usage: $0 [options]

Target Selection (choose one):
    --workspace         Audit OpenClaw workspace documentation
    --athena-web        Audit athena-web project documentation
    --path PATH         Audit specific directory

Document Types (can specify multiple):
    --type readme               Review README files
    --type skills               Review SKILL.md files
    --type jsdoc                Review JSDoc comments
    --type inline-comments      Review inline code comments
    --type api-docs             Review API documentation
    --type all                  Review all documentation types (default)

Focus Areas (can specify multiple):
    --focus clarity             Focus on clarity and readability
    --focus completeness        Focus on missing information
    --focus examples            Focus on code/usage examples
    --focus consistency         Focus on terminology and style
    --focus technical-accuracy  Focus on correctness
    --focus all                 Evaluate all dimensions (default)

Output:
    --format human              Human-readable markdown (default)
    --format json               Structured JSON output

Model:
    --model haiku               Fast, for quick checks
    --model sonnet              Balanced (default)
    --model opus                Comprehensive, for critical docs

Calibration:
    --calibrate reject --audit-id ID --finding-id N
                                Reject a false positive finding

Examples:
    # Full workspace audit
    $0 --workspace

    # Audit only README files
    $0 --workspace --type readme

    # Audit athena-web API docs, focus on examples
    $0 --athena-web --type api-docs --focus examples

    # Generate JSON for scripting
    $0 --workspace --format json > audit.json

    # Quick check with Haiku
    $0 --workspace --model haiku

EOF
    exit 1
}

log_section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}"
}

log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Parse command-line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --workspace)
                TARGET_PATH="$WORKSPACE_DIR"
                shift
                ;;
            --athena-web)
                TARGET_PATH="$ATHENA_WEB_DIR"
                shift
                ;;
            --path)
                TARGET_PATH="$2"
                shift 2
                ;;
            --type)
                DOC_TYPES+=("$2")
                shift 2
                ;;
            --focus)
                FOCUS_AREAS+=("$2")
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --model)
                MODEL="$2"
                shift 2
                ;;
            --calibrate)
                AUDIT_MODE="calibrate"
                shift
                ;;
            --audit-id)
                CALIBRATE_AUDIT_ID="$2"
                shift 2
                ;;
            --finding-id)
                CALIBRATE_FINDING_ID="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate target path (skip for calibration mode)
    if [[ "$AUDIT_MODE" != "calibrate" ]]; then
        if [[ -z "$TARGET_PATH" ]]; then
            log_error "Must specify --workspace, --athena-web, or --path"
            exit 1
        fi

        if [[ ! -d "$TARGET_PATH" ]]; then
            log_error "Target path does not exist: $TARGET_PATH"
            exit 1
        fi
    fi

    # Default to all types if none specified
    if [[ ${#DOC_TYPES[@]} -eq 0 ]]; then
        DOC_TYPES=("all")
    fi

    # Default to all focus areas if none specified
    if [[ ${#FOCUS_AREAS[@]} -eq 0 ]]; then
        FOCUS_AREAS=("all")
    fi

    # Validate doc types
    for dtype in "${DOC_TYPES[@]}"; do
        if [[ ! " ${VALID_DOC_TYPES[@]} " =~ " ${dtype} " ]]; then
            log_error "Invalid document type: $dtype"
            log_error "Valid types: ${VALID_DOC_TYPES[*]}"
            exit 1
        fi
    done

    # Validate focus areas
    for focus in "${FOCUS_AREAS[@]}"; do
        if [[ ! " ${VALID_FOCUS[@]} " =~ " ${focus} " ]]; then
            log_error "Invalid focus area: $focus"
            log_error "Valid focus areas: ${VALID_FOCUS[*]}"
            exit 1
        fi
    done

    # Validate output format
    if [[ ! " ${VALID_FORMATS[@]} " =~ " ${OUTPUT_FORMAT} " ]]; then
        log_error "Invalid output format: $OUTPUT_FORMAT"
        log_error "Valid formats: ${VALID_FORMATS[*]}"
        exit 1
    fi
}

# Find documentation files based on type
find_docs() {
    local doc_type="$1"
    local target="$2"
    local files=()

    case "$doc_type" in
        readme)
            mapfile -t files < <(find "$target" -type f -iname "README*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)  # REASON: skip permission-noise while crawling large trees.
            ;;
        skills)
            mapfile -t files < <(find "$target" -type f -name "SKILL.md" -not -path "*/node_modules/*" 2>/dev/null)  # REASON: skip permission-noise while crawling large trees.
            ;;
        jsdoc)
            mapfile -t files < <(find "$target" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)  # REASON: skip permission-noise while crawling large trees.
            ;;
        inline-comments)
            mapfile -t files < <(find "$target" -type f \( -name "*.sh" -o -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.rs" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/target/*" 2>/dev/null)  # REASON: skip permission-noise while crawling large trees.
            ;;
        api-docs)
            # Look for API-related documentation
            mapfile -t files < <(find "$target" -type f \( -iname "*api*.md" -o -path "*/routes/*.js" -o -path "*/api/*.js" \) -not -path "*/node_modules/*" 2>/dev/null)  # REASON: skip permission-noise while crawling large trees.
            ;;
        all)
            # Combine all types
            local all_files=()
            for type in readme skills jsdoc inline-comments api-docs; do
                mapfile -t type_files < <(find_docs "$type" "$target")
                all_files+=("${type_files[@]}")
            done
            # Remove duplicates
            mapfile -t files < <(printf '%s\n' "${all_files[@]}" | sort -u)
            ;;
    esac

    printf '%s\n' "${files[@]}"
}

# Generate audit prompt
generate_prompt() {
    local target="$1"
    local files_list="$2"
    local timestamp="$3"

    local doc_types_str=$(IFS=,; echo "${DOC_TYPES[*]}")
    local focus_areas_str=$(IFS=,; echo "${FOCUS_AREAS[*]}")

    cat << EOF
# Documentation Audit Request

You are a documentation quality auditor. Your task is to systematically review documentation and provide actionable improvement recommendations.

## Audit Configuration

- **Target**: $target
- **Document Types**: $doc_types_str
- **Focus Areas**: $focus_areas_str
- **Timestamp**: $timestamp

## Files to Review

$files_list

## Quality Dimensions

Evaluate each document across these dimensions:

### 1. Clarity (0-10)
- Clear purpose and scope
- Plain language (no unexplained jargon)
- Logical information flow
- Concise (no unnecessary verbosity)
- Good formatting (headings, lists, code blocks)

### 2. Completeness (0-10)
- Context and motivation provided
- Prerequisites clearly stated
- All essential information present
- Edge cases and limitations documented
- Troubleshooting guidance included

### 3. Examples (0-10)
- Concrete usage examples provided
- Examples are copy-pasteable
- Cover common and important scenarios
- Expected output shown
- Examples progress from simple to complex

### 4. Consistency (0-10)
- Terminology consistent across docs
- Uniform formatting and style
- Follows project conventions
- Cross-references are accurate
- Docs match current code state

### 5. Technical Accuracy (0-10)
- Information is factually correct
- Reflects current implementation
- Technical details are precise
- Code examples execute correctly
- API signatures and parameters accurate

## Output Format

Produce a JSON object with this structure:

\`\`\`json
{
  "audit_id": "da-<timestamp>-<target-name>",
  "target": "<full-path>",
  "scope": ["<doc-types>"],
  "audited_at": "<ISO-8601-timestamp>",
  "overall_score": <0-10>,
  "summary": "<1-2 paragraph high-level assessment>",
  "documents_reviewed": <count>,
  "files_reviewed": [
    {
      "path": "<relative-path>",
      "type": "<doc-type>",
      "score": <0-10>,
      "clarity": <0-10>,
      "completeness": <0-10>,
      "examples": <0-10>,
      "consistency": <0-10>,
      "technical_accuracy": <0-10>,
      "issues": [
        {
          "severity": "major|minor|suggestion",
          "line": <line-number-or-null>,
          "category": "<clarity|completeness|examples|consistency|technical-accuracy>",
          "issue": "<what's wrong>",
          "recommendation": "<how to fix>",
          "example": "<optional code example>"
        }
      ],
      "strengths": [
        "<positive observation 1>",
        "<positive observation 2>"
      ]
    }
  ],
  "findings": [
    {
      "severity": "major|minor|suggestion",
      "file": "<path>",
      "line": <line-number-or-null>,
      "category": "<category>",
      "issue": "<description>",
      "recommendation": "<action>",
      "example": "<optional>"
    }
  ],
  "strengths": [
    "<overall strength 1>",
    "<overall strength 2>"
  ],
  "improvement_priorities": [
    {
      "priority": "high|medium|low",
      "area": "<what to improve>",
      "impact": "<why it matters>",
      "effort": "<hours or 'quick'>"
    }
  ],
  "metrics": {
    "readme_coverage": <0-100>,
    "skill_docs_coverage": <0-100>,
    "inline_comment_coverage": <0-100>,
    "jsdoc_coverage": <0-100>,
    "avg_readability_score": <0-100>
  }
}
\`\`\`

## Severity Definitions

- **major**: Critical information missing, seriously unclear, or misleading. Blocks user success.
- **minor**: Suboptimal clarity, missing helpful details, or minor inconsistency. Reduces effectiveness.
- **suggestion**: Opportunity for improvement, style preference, or nice-to-have addition.

## Instructions

1. Read each file carefully
2. Evaluate against the five quality dimensions
3. Identify specific issues with line numbers when possible
4. Provide actionable recommendations (not just "improve clarity")
5. Note strengths to reinforce good practices
6. Calculate metrics based on actual coverage
7. Prioritize improvements by impact and effort
8. Output ONLY the JSON object (no markdown wrapper, no explanatory text)

## Special Considerations

### For SKILL.md files
Validate these required sections exist:
- Frontmatter (name, description)
- Purpose/overview
- Invocation examples
- Input/output structure
- Integration points
- Exit codes (if applicable)

### For README files
Check for:
- Clear project purpose
- Installation/setup instructions
- Basic usage examples
- Links to detailed docs (if needed)

### For inline comments
Evaluate:
- Complex logic is explained
- Non-obvious decisions documented
- Comments are accurate (not outdated)
- Ratio of high-value comments to noise

### For JSDoc
Verify:
- Function purpose clear
- Parameters documented with types
- Return values described
- Exceptions listed

### For API docs
Confirm:
- Endpoint paths and methods correct
- Request/response schemas complete
- Authentication requirements clear
- Error codes documented
- Examples provided (curl or code)

Begin audit now. Output JSON only.
EOF
}

# Run calibration mode
run_calibration() {
    if [[ -z "${CALIBRATE_AUDIT_ID:-}" ]] || [[ -z "${CALIBRATE_FINDING_ID:-}" ]]; then
        log_error "Calibration requires --audit-id and --finding-id"
        exit 1
    fi

    mkdir -p "$(dirname "$CALIBRATION_FILE")"

    local calibration_entry=$(jq -n \
        --arg audit_id "$CALIBRATE_AUDIT_ID" \
        --arg finding_id "$CALIBRATE_FINDING_ID" \
        --arg action "reject" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{audit_id: $audit_id, finding_id: ($finding_id | tonumber), action: $action, timestamp: $timestamp}')

    echo "$calibration_entry" >> "$CALIBRATION_FILE"
    log_ok "Calibration recorded: audit $CALIBRATE_AUDIT_ID, finding $CALIBRATE_FINDING_ID rejected"
    exit 0
}

# Run full audit
run_audit() {
    local target="$TARGET_PATH"
    local target_name=$(basename "$target")
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local timestamp_short=$(date -u +%Y%m%d-%H%M%S)
    local audit_id="da-${timestamp_short}-${target_name}"

    log_section "Documentation Audit: $target_name"
    log_info "Target: $target"
    log_info "Types: ${DOC_TYPES[*]}"
    log_info "Focus: ${FOCUS_AREAS[*]}"
    log_info "Model: $MODEL"
    echo ""

    # Collect files
    log_info "Collecting documentation files..."
    local all_files=()
    for doc_type in "${DOC_TYPES[@]}"; do
        mapfile -t type_files < <(find_docs "$doc_type" "$target")
        if [[ ${#type_files[@]} -gt 0 ]]; then
            log_ok "Found ${#type_files[@]} $doc_type file(s)"
            all_files+=("${type_files[@]}")
        else
            log_warn "No $doc_type files found"
        fi
    done

    # Remove duplicates
    mapfile -t all_files < <(printf '%s\n' "${all_files[@]}" | sort -u)

    if [[ ${#all_files[@]} -eq 0 ]]; then
        log_error "No documentation files found"
        exit 1
    fi

    log_ok "Total files to review: ${#all_files[@]}"

    # Generate files list for prompt
    local files_list=""
    for file in "${all_files[@]}"; do
        local rel_path="${file#$target/}"
        files_list+="- $rel_path\n"
    done

    # Generate prompt
    log_info "Generating audit prompt..."
    local prompt=$(generate_prompt "$target" "$(echo -e "$files_list")" "$timestamp")

    # Create temporary prompt file
    local temp_prompt=$(mktemp)
    echo "$prompt" > "$temp_prompt"

    # Append file contents to prompt (sample first 200 lines of each file to stay within context limits)
    echo -e "\n## File Contents\n" >> "$temp_prompt"
    for file in "${all_files[@]}"; do
        local rel_path="${file#$target/}"
        echo -e "\n### File: $rel_path\n" >> "$temp_prompt"
        echo '```' >> "$temp_prompt"
        head -200 "$file" >> "$temp_prompt"
        local line_count=$(wc -l < "$file")
        if [[ $line_count -gt 200 ]]; then
            echo -e "\n... (truncated, $line_count total lines)" >> "$temp_prompt"
        fi
        echo '```' >> "$temp_prompt"
    done

    # Run Claude
    log_info "Running audit with Claude $MODEL..."
    local audit_json=""
    if audit_json=$(claude -p --model "$MODEL" < "$temp_prompt" 2>&1); then
        log_ok "Audit completed"
    else
        log_error "Claude execution failed: $audit_json"
        rm -f "$temp_prompt"
        exit 1
    fi

    rm -f "$temp_prompt"

    # Extract JSON from output
    local clean_json=$(echo "$audit_json" | sed -n '/^{/,/^}/p' | head -1)

    # Validate JSON
    if [[ -z "$clean_json" ]] || ! echo "$clean_json" | jq empty >/dev/null; then
        log_error "Invalid JSON output from Claude"
        echo "$audit_json" >&2
        exit 1
    fi

    # Ensure audits directory exists
    mkdir -p "$AUDITS_DIR"

    # Write audit to file
    local audit_file="$AUDITS_DIR/${audit_id}.json"
    echo "$clean_json" | jq '.' > "$audit_file"
    log_ok "Audit saved to: $audit_file"

    # Output based on format
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        # Output JSON directly
        cat "$audit_file"
    else
        # Generate human-readable output
        generate_human_report "$audit_file"
    fi

    # Check if score is critically low
    local overall_score=$(jq -r '.overall_score // 0' "$audit_file")
    if (( $(echo "$overall_score < 5.0" | bc -l) )); then
        log_error "Documentation quality critically low (score: $overall_score)"
        exit 2
    fi

    exit 0
}

# Generate human-readable report
generate_human_report() {
    local audit_file="$1"

    local audit_id=$(jq -r '.audit_id' "$audit_file")
    local target=$(jq -r '.target' "$audit_file")
    local audited_at=$(jq -r '.audited_at' "$audit_file")
    local overall_score=$(jq -r '.overall_score' "$audit_file")
    local summary=$(jq -r '.summary' "$audit_file")
    local docs_reviewed=$(jq -r '.documents_reviewed' "$audit_file")

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Documentation Audit Report                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Audit ID:${NC} $audit_id"
    echo -e "${CYAN}Target:${NC} $target"
    echo -e "${CYAN}Date:${NC} $audited_at"
    echo -e "${CYAN}Documents Reviewed:${NC} $docs_reviewed"
    echo ""

    # Overall score with color
    local score_color="$GREEN"
    if (( $(echo "$overall_score < 7.0" | bc -l) )); then
        score_color="$YELLOW"
    fi
    if (( $(echo "$overall_score < 5.0" | bc -l) )); then
        score_color="$RED"
    fi
    echo -e "${CYAN}Overall Score:${NC} ${score_color}${overall_score}/10${NC}"
    echo ""

    log_section "Summary"
    echo "$summary"

    # Files reviewed
    log_section "Files Reviewed"
    local files_count=$(jq -r '.files_reviewed | length' "$audit_file")
    for ((i=0; i<files_count; i++)); do
        local path=$(jq -r ".files_reviewed[$i].path" "$audit_file")
        local score=$(jq -r ".files_reviewed[$i].score" "$audit_file")
        local issues_count=$(jq -r ".files_reviewed[$i].issues | length" "$audit_file")

        local file_color="$GREEN"
        if (( $(echo "$score < 7.0" | bc -l) )); then
            file_color="$YELLOW"
        fi
        if (( $(echo "$score < 5.0" | bc -l) )); then
            file_color="$RED"
        fi

        if [[ $issues_count -gt 0 ]]; then
            echo -e "${file_color}⚠${NC} $path (${file_color}${score}/10${NC}) - $issues_count issue(s)"
        else
            echo -e "${GREEN}✓${NC} $path (${file_color}${score}/10${NC})"
        fi
    done

    # Findings by severity
    local major_count=$(jq -r '[.findings[] | select(.severity == "major")] | length' "$audit_file")
    local minor_count=$(jq -r '[.findings[] | select(.severity == "minor")] | length' "$audit_file")
    local suggestion_count=$(jq -r '[.findings[] | select(.severity == "suggestion")] | length' "$audit_file")

    if [[ $major_count -gt 0 ]]; then
        log_section "Major Issues ($major_count)"
        jq -r '.findings[] | select(.severity == "major") | "• \(.file):\(.line // "?"): [\(.category)] \(.issue)\n  → \(.recommendation)"' "$audit_file"
    fi

    if [[ $minor_count -gt 0 ]]; then
        log_section "Minor Issues ($minor_count)"
        jq -r '.findings[] | select(.severity == "minor") | "• \(.file):\(.line // "?"): [\(.category)] \(.issue)\n  → \(.recommendation)"' "$audit_file" | head -20
        if [[ $minor_count -gt 20 ]]; then
            echo -e "\n${YELLOW}... and $((minor_count - 20)) more minor issues${NC}"
        fi
    fi

    if [[ $suggestion_count -gt 0 ]]; then
        log_section "Suggestions ($suggestion_count)"
        jq -r '.findings[] | select(.severity == "suggestion") | "• \(.file): \(.issue)"' "$audit_file" | head -10
        if [[ $suggestion_count -gt 10 ]]; then
            echo -e "\n${CYAN}... and $((suggestion_count - 10)) more suggestions${NC}"
        fi
    fi

    # Strengths
    local strengths_count=$(jq -r '.strengths | length' "$audit_file")
    if [[ $strengths_count -gt 0 ]]; then
        log_section "Strengths"
        jq -r '.strengths[] | "✓ \(.)"' "$audit_file"
    fi

    # Improvement priorities
    log_section "Improvement Priorities"
    local priorities_count=$(jq -r '.improvement_priorities | length' "$audit_file")
    for ((i=0; i<priorities_count; i++)); do
        local priority=$(jq -r ".improvement_priorities[$i].priority" "$audit_file")
        local area=$(jq -r ".improvement_priorities[$i].area" "$audit_file")
        local impact=$(jq -r ".improvement_priorities[$i].impact" "$audit_file")
        local effort=$(jq -r ".improvement_priorities[$i].effort" "$audit_file")

        local priority_color="$CYAN"
        if [[ "$priority" == "high" ]]; then
            priority_color="$RED"
        elif [[ "$priority" == "medium" ]]; then
            priority_color="$YELLOW"
        fi

        echo -e "${priority_color}$((i+1)). [$priority]${NC} $area"
        echo -e "   Impact: $impact"
        echo -e "   Effort: $effort"
    done

    # Metrics
    log_section "Metrics"
    local readme_cov=$(jq -r '.metrics.readme_coverage // "N/A"' "$audit_file")
    local skill_cov=$(jq -r '.metrics.skill_docs_coverage // "N/A"' "$audit_file")
    local inline_cov=$(jq -r '.metrics.inline_comment_coverage // "N/A"' "$audit_file")
    local jsdoc_cov=$(jq -r '.metrics.jsdoc_coverage // "N/A"' "$audit_file")
    local readability=$(jq -r '.metrics.avg_readability_score // "N/A"' "$audit_file")

    echo "  README Coverage:        ${readme_cov}%"
    echo "  SKILL.md Coverage:      ${skill_cov}%"
    echo "  Inline Comment Coverage: ${inline_cov}%"
    echo "  JSDoc Coverage:         ${jsdoc_cov}%"
    echo "  Avg Readability Score:  ${readability}"

    echo ""
    echo -e "${CYAN}Full report:${NC} $audit_file"
    echo ""
}

# Main execution
main() {
    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    if ! command -v claude &>/dev/null; then
        log_error "claude CLI is required but not installed"
        exit 1
    fi

    parse_args "$@"

    if [[ "$AUDIT_MODE" == "calibrate" ]]; then
        run_calibration
    else
        run_audit
    fi
}

main "$@"
