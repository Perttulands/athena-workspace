#!/usr/bin/env bash
# analyze-patterns.sh - Pattern detection and analysis logic

set -euo pipefail

# Analyze all runs and compute template metrics
analyze_runs() {
  local template_filter="$1"
  local runs_data="[]"

  # Parse all run JSON files
  for run_file in "$RUNS_DIR"/*.json; do
    [[ -f "$run_file" ]] || continue

    local run_data
    if jq -e . "$run_file" >/dev/null 2>&1; then
      run_data=$(jq -c '. + {run_file: "'$(basename "$run_file")'"}' "$run_file")
    else
      run_data='{}'
    fi

    # Skip empty/invalid JSON
    if [[ "$run_data" == "{}" ]]; then
      continue
    fi

    runs_data=$(jq --argjson item "$run_data" '. + [$item]' <<<"$runs_data")
  done

  # Group by template and compute metrics
  local template_metrics
  template_metrics=$(jq -f "$SCRIPT_DIR/jq-filters/group-runs.jq" <<<"$runs_data")

  # Filter by template if specified
  if [[ -n "$template_filter" ]]; then
    template_metrics=$(jq --arg tpl "$template_filter" '[.[] | select(.template == $tpl or .template == ($tpl + ".md"))]' <<<"$template_metrics")
  fi

  echo "$template_metrics"
}

# Identify issues based on metrics
identify_issues() {
  local metrics="$1"

  jq -f "$SCRIPT_DIR/jq-filters/identify-issues.jq" <<<"$metrics"
}

# Generate recommendations based on issues
generate_recommendations() {
  local issues="$1"

  jq -f "$SCRIPT_DIR/jq-filters/generate-recommendations.jq" <<<"$issues"
}

# Generate human-readable report
generate_human_report() {
  local template_filter="$1"

  echo "=== Prompt Optimization Report ==="
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  local metrics
  metrics=$(analyze_runs "$template_filter")

  local total_runs
  total_runs=$(jq '[.[] | .total_runs] | add // 0' <<<"$metrics")
  echo "Analyzed $total_runs total runs"
  echo ""

  local issues
  issues=$(identify_issues "$metrics")

  local recommendations
  recommendations=$(generate_recommendations "$issues")

  # Print per-template analysis
  local report_script='
.[] |
"Template: " + .template + "\n" +
"  Total Runs: " + (.total_runs | tostring) + "\n" +
"  Success Rate: " + (if .total_runs > 0 then ((.successful / .total_runs * 100) | floor | tostring) + "%" else "N/A" end) + " (" + (.successful | tostring) + "/" + (.total_runs | tostring) + ")\n" +
"  Retry Rate: " + (if .total_runs > 0 then ((.retries / .total_runs * 100) | floor | tostring) + "%" else "N/A" end) + "\n" +
(if (.durations | length > 0) then "  Avg Duration: " + ((.durations | add / length) | floor | tostring) + "s\n" else "" end) +
"\n" +
(if (.issues | length > 0) then
  "  Issues Identified:\n" +
  (.issues | map("    - [" + .severity + "] " + .description) | join("\n")) + "\n\n" +
  "  Recommendations:\n" +
  (.issues | map(.recommendations // []) | flatten | to_entries | map("    " + ((.key + 1) | tostring) + ". [" + .value.section + "] " + .value.suggestion) | join("\n")) + "\n"
else
  "  No issues identified. Template performing well.\n"
end) +
"\n---\n"
'

  jq -r "$report_script" <<<"$recommendations"
}

# Generate JSON report
generate_json_report() {
  local template_filter="$1"

  local metrics
  metrics=$(analyze_runs "$template_filter")

  local issues
  issues=$(identify_issues "$metrics")

  local recommendations
  recommendations=$(generate_recommendations "$issues")

  # Combine metrics and recommendations
  jq -s -f "$SCRIPT_DIR/jq-filters/json-report.jq" <(echo "$metrics") <(echo "$recommendations")
}

# Generate A/B test variant
generate_ab_test_variant() {
  local template_name="$1"
  local template_file="$TEMPLATES_DIR/${template_name}.md"
  local variant_file="$TEMPLATES_DIR/${template_name}-v2.md"

  if [[ ! -f "$template_file" ]]; then
    echo "Error: Template not found: $template_file" >&2
    exit 1
  fi

  # Analyze this template specifically
  local report
  report=$(generate_json_report "$template_name")

  local template_data
  template_data=$(jq '.templates[0]' <<<"$report")

  if [[ "$template_data" == "null" ]]; then
    echo "Error: No run data found for template: $template_name" >&2
    exit 1
  fi

  # Extract top recommendations
  local top_recs
  top_recs=$(jq -r '.issues | map(.recommendations // []) | flatten | .[0:3] | map(.suggestion) | join("\n")' <<<"$template_data")

  if [[ -z "$top_recs" || "$top_recs" == "null" ]]; then
    echo "No recommendations generated for $template_name (template may already be optimal)"
    exit 0
  fi

  # Create variant with inline comments showing recommended changes
  mkdir -p "$AB_TEST_DIR"

  cp "$template_file" "$variant_file"

  # Add header annotation
  local header_note="<!-- A/B Test Variant v2 - Generated $(date -u +%Y-%m-%d) -->
<!-- Original: ${template_name}.md -->
<!-- Optimizations applied based on run history analysis -->

"
  echo -e "${header_note}$(cat "$variant_file")" > "$variant_file"

  # Create comparison metadata
  local comparison_file="$AB_TEST_DIR/${template_name}-comparison.json"
  jq -n \
    --arg orig "$template_name.md" \
    --arg variant "${template_name}-v2.md" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson metrics "$(jq '.metrics' <<<"$template_data")" \
    --argjson recs "$(jq '[.issues | map(.recommendations // []) | flatten | .[0:3]]' <<<"$template_data")" \
    '{
      original: $orig,
      variant: $variant,
      created_at: $created,
      baseline_metrics: $metrics,
      optimizations_applied: $recs,
      test_status: "active",
      dispatch_strategy: "round_robin",
      target_sample_size: 10
    }' > "$comparison_file"

  echo "Generated A/B test variant:"
  echo "  Original:    $template_file"
  echo "  Variant:     $variant_file"
  echo "  Comparison:  $comparison_file"
  echo ""
  echo "Recommended changes (review and apply manually to variant):"
  echo "$top_recs"
  echo ""
  echo "Next steps:"
  echo "1. Review and manually edit $variant_file to apply optimizations"
  echo "2. Use both templates in round-robin dispatch for next 10 runs"
  echo "3. Re-run optimizer to compare success rates"
}
