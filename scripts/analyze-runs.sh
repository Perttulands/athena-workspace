#!/usr/bin/env bash
# analyze-runs.sh — Flywheel analysis for agentic coding swarm
#
# Parses all JSON run/result records and generates a summary report with:
# - Success/failure rates, durations, retry patterns
# - Performance breakdown by agent type (claude vs codex)
# - Common failure reasons and recommendations
#
# Usage:
#   ./scripts/analyze-runs.sh                    # Human-readable report
#   ./scripts/analyze-runs.sh --json             # Machine-readable JSON
#   ./scripts/analyze-runs.sh --since 2026-02-11 # Filter by date (YYYY-MM-DD)
#
# Dependencies: jq (required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
RUNS_DIR="$WORKSPACE_ROOT/state/runs"
RESULTS_DIR="$WORKSPACE_ROOT/state/results"

# Options
OUTPUT_JSON=false
SINCE_DATE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --since)
      SINCE_DATE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--json] [--since YYYY-MM-DD]" >&2
      exit 1
      ;;
  esac
done

# Check dependencies
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

collect_json_records() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "[]"; return 0; }
  local -a files=()
  mapfile -t files < <(find "$dir" -name "*.json" -type f)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  jq -s '.' "${files[@]}"
}

# Collect all run and result records
runs="$(collect_json_records "$RUNS_DIR")"
results="$(collect_json_records "$RESULTS_DIR")"

# Merge runs and results by bead ID
merged=$(jq -n \
  --argjson runs "$runs" \
  --argjson results "$results" \
  '
  # Index results by bead
  ($results | map({(.bead): .}) | add) as $results_map |

  # Merge each run with its result
  $runs | map(
    . as $run |
    ($results_map[$run.bead] // {}) as $result |
    $run + {
      result_status: ($result.status // null),
      result_finished_at: ($result.finished_at // null),
      result_reason: ($result.reason // null)
    }
  )
  ')

# Apply date filter if specified
if [[ -n "$SINCE_DATE" ]]; then
  merged=$(echo "$merged" | jq --arg since "$SINCE_DATE" '
    map(select(
      .started_at >= $since or
      (.result_finished_at // .started_at) >= $since
    ))
  ')
fi

# Calculate statistics
# Note: Some legacy records have placeholder timestamp "'$START'" (literal string with quotes)
stats=$(echo "$merged" | jq --arg placeholder "'\$START'" '
  # Basic counts
  length as $total |

  # Status counts
  (map(select(.result_status == "done")) | length) as $success |
  (map(select(.result_status == "failed")) | length) as $failed |
  (map(select(.result_status == "timeout")) | length) as $timeout |
  (map(select(.result_status == null or .result_status == "running")) | length) as $running |

  # Success rate
  (if $total > 0 then ($success / $total * 100) else 0 end) as $success_rate |

  # Retry analysis
  (map(select(.attempt > 1)) | length) as $retries |
  (if $total > 0 then ($retries / $total * 100) else 0 end) as $retry_rate |

  # Duration calculations (only for completed tasks with valid timestamps)
  (map(
    select(.result_finished_at and .started_at and .started_at != $placeholder) |
    ((.result_finished_at | fromdateiso8601) - (.started_at | fromdateiso8601))
  )) as $durations |

  (if ($durations | length) > 0 then
    ($durations | add / length)
  else 0 end) as $avg_duration |

  # Agent type breakdown
  (group_by(.agent) | map({
    agent: .[0].agent,
    count: length,
    success: (map(select(.result_status == "done")) | length),
    failed: (map(select(.result_status == "failed")) | length),
    avg_duration: (
      [.[] |
       select(.result_finished_at and .started_at and .started_at != $placeholder) |
       ((.result_finished_at | fromdateiso8601) - (.started_at | fromdateiso8601))
      ] as $agent_durations |
      if ($agent_durations | length) > 0 then
        ($agent_durations | add / length)
      else 0 end
    )
  })) as $by_agent |

  # Model breakdown
  (group_by(.model) | map({
    model: .[0].model,
    count: length,
    success: (map(select(.result_status == "done")) | length)
  })) as $by_model |

  # Template breakdown
  (group_by(.template_name // "custom") | map({
    template: (.[0].template_name // "custom"),
    count: length,
    success: (map(select(.result_status == "done")) | length),
    avg_duration: (
      [.[] |
       select(.result_finished_at and .started_at and .started_at != $placeholder) |
       ((.result_finished_at | fromdateiso8601) - (.started_at | fromdateiso8601))
      ] as $template_durations |
      if ($template_durations | length) > 0 then
        ($template_durations | add / length)
      else 0 end
    )
  })) as $by_template |

  # Failure reasons
  (map(select(.result_status == "failed" and .result_reason)) |
   group_by(.result_reason) |
   map({reason: .[0].result_reason, count: length}) |
   sort_by(-.count)
  ) as $failure_reasons |

  # Task patterns (extract from prompt)
  (map(
    .prompt as $p |
    if ($p | test("^Build ")) then "build"
    elif ($p | test("^Fix ")) then "fix"
    elif ($p | test("^Update ")) then "update"
    elif ($p | test("^Review ")) then "review"
    elif ($p | test("^Design ")) then "design"
    elif ($p | test("^Implement ")) then "implement"
    else "other"
    end
  ) | group_by(.) | map({
    task_type: .[0],
    count: length
  })) as $task_types |

  {
    total_runs: $total,
    success: $success,
    failed: $failed,
    timeout: $timeout,
    running: $running,
    success_rate: $success_rate,
    retry_count: $retries,
    retry_rate: $retry_rate,
    avg_duration_seconds: $avg_duration,
    by_agent: $by_agent,
    by_model: $by_model,
    by_template: $by_template,
    failure_reasons: $failure_reasons,
    task_types: $task_types
  }
')

# Generate recommendations (as JSON array)
# Build recommendations by checking metrics against thresholds
recommendations=$(jq -n --argjson stats "$stats" '
  [] |

  # Low success rate
  if ($stats.success_rate < 70 and $stats.total_runs >= 3) then
    . + ["Overall success rate (\($stats.success_rate | floor)%) is below target (70%). Review prompt templates and task decomposition."]
  else . end |

  # High retry rate
  if ($stats.retry_rate > 30 and $stats.total_runs >= 3) then
    . + ["High retry rate (\($stats.retry_rate | floor)%). Consider improving initial prompt quality or agent context."]
  else . end |

  # Agent-specific issues
  if ($stats.by_agent | length > 0) then
    ($stats.by_agent[] | select(.count >= 2 and ((.success / .count * 100) < 60))) as $weak_agent |
    if $weak_agent then
      . + ["Agent \($weak_agent.agent) has low success rate (\(($weak_agent.success / $weak_agent.count * 100) | floor)%). May need better prompts or different task assignment."]
    else . end
  else . end |

  # Common failure patterns
  if (($stats.failure_reasons | length) > 0) then
    . + ["Most common failure: \"\($stats.failure_reasons[0].reason)\" (\($stats.failure_reasons[0].count) occurrences)"]
  else . end |

  # Default message if no issues
  if length == 0 then
    ["All metrics within acceptable ranges. Continue monitoring."]
  else . end
' 2>&1)

if [[ -z "$recommendations" ]]; then
  echo "ERROR: Failed to generate recommendations" >&2
  recommendations='["Error generating recommendations"]'
fi

# Output results
if $OUTPUT_JSON; then
  # Machine-readable JSON output
  jq -n \
    --argjson stats "$stats" \
    --argjson recs "$recommendations" \
    --argjson data "$merged" \
    '{
      generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      filter: {since: $ENV.SINCE_DATE},
      statistics: $stats,
      recommendations: $recs,
      raw_data: $data
    }'
else
  # Human-readable report
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "FLYWHEEL ANALYSIS REPORT"
  echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  if [[ -n "$SINCE_DATE" ]]; then
    echo "Filter: Since $SINCE_DATE"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  echo "SUMMARY"
  echo "$stats" | jq -r '
    "  Total runs:     \(.total_runs)",
    "  Success:        \(.success) (\(.success_rate | floor)%)",
    "  Failed:         \(.failed)",
    "  Timeout:        \(.timeout)",
    "  Running:        \(.running)",
    "  Retries:        \(.retry_count) (\(.retry_rate | floor)% of runs)",
    "  Avg duration:   \(.avg_duration_seconds | floor)s"
  '
  echo

  echo "BY AGENT TYPE"
  echo "$stats" | jq -r '
    .by_agent[] |
    "  \(.agent | ascii_upcase):",
    "    Runs:         \(.count)",
    "    Success:      \(.success) (\((.success / .count * 100) | floor)%)",
    "    Failed:       \(.failed)",
    "    Avg duration: \(.avg_duration | floor)s",
    ""
  '

  echo "BY MODEL"
  echo "$stats" | jq -r '
    .by_model[] |
    "  \(.model):",
    "    Runs:    \(.count)",
    "    Success: \(.success)",
    ""
  '

  echo "BY TEMPLATE"
  echo "$stats" | jq -r '
    .by_template[] |
    "  \(.template):",
    "    Runs:         \(.count)",
    "    Success:      \(.success) (\((.success / .count * 100) | floor)%)",
    "    Avg duration: \(.avg_duration | floor)s",
    ""
  '

  echo "BY TASK TYPE"
  echo "$stats" | jq -r '
    .task_types[] |
    "  \(.task_type | ascii_upcase): \(.count)"
  '
  echo

  if [[ "$(echo "$stats" | jq '.failure_reasons | length')" -gt 0 ]]; then
    echo "FAILURE REASONS"
    echo "$stats" | jq -r '
      .failure_reasons[] |
      "  [\(.count)x] \(.reason)"
    '
    echo
  fi

  echo "RECOMMENDATIONS"
  echo "$recommendations" | jq -r '.[] | "  • \(.)"'
  echo

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
