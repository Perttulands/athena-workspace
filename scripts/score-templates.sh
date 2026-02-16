#!/usr/bin/env bash
# score-templates.sh — Template scoring from run history
#
# Analyzes all run records to calculate success rates, average durations,
# and retry patterns per prompt template. Outputs structured scores that
# feed into template selection decisions.
#
# Usage:
#   ./scripts/score-templates.sh              # Human-readable output + write JSON
#   ./scripts/score-templates.sh --json       # Machine-readable JSON only
#
# Outputs:
#   state/template-scores.json — Structured scoring data
#
# Dependencies: jq (required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
RUNS_DIR="$WORKSPACE_ROOT/state/runs"
OUTPUT_FILE="$WORKSPACE_ROOT/state/template-scores.json"

# Options
OUTPUT_JSON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--json]"
      echo
      echo "Analyzes run records to score prompt templates by success rate and performance."
      echo
      echo "Options:"
      echo "  --json    Output machine-readable JSON only (no human text)"
      echo "  --help    Show this help message"
      echo
      echo "Outputs:"
      echo "  state/template-scores.json — Structured scoring data"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--json]" >&2
      exit 1
      ;;
  esac
done

# Check dependencies
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

# Collect all run records
if [[ ! -d "$RUNS_DIR" ]]; then
  echo "Error: Runs directory not found: $RUNS_DIR" >&2
  exit 1
fi

collect_run_records() {
  local dir="$1"
  local -a files=()
  mapfile -t files < <(find "$dir" -name "*.json" -type f)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  jq -s '.' "${files[@]}"
}

runs="$(collect_run_records "$RUNS_DIR")"

# Calculate template scores
scores=$(echo "$runs" | jq '
  # Group by template_name (default to "custom" if null)
  group_by(.template_name // "custom") |

  # Calculate metrics for each template
  map({
    template: (.[0].template_name // "custom"),
    uses: length,
    success_rate: (
      (map(select(.status == "done")) | length) / length
    ),
    avg_duration_s: (
      if (map(select(.duration_seconds != null)) | length) > 0 then
        (map(select(.duration_seconds != null) | .duration_seconds) | add / length)
      else
        0
      end
    ),
    avg_retries: (
      if length > 0 then
        (map(.attempt - 1) | add / length)
      else
        0
      end
    )
  }) |

  # Sort by uses (most popular first)
  sort_by(-.uses) |

  # Convert to object indexed by template name
  map({(.template): {
    uses: .uses,
    success_rate: .success_rate,
    avg_duration_s: (.avg_duration_s | floor),
    avg_retries: (.avg_retries | . * 10 | floor / 10)
  }}) |
  add
')

# Generate recommendation
recommendation=$(echo "$scores" | jq -r '
  # Find worst template (lowest success rate with at least 2 uses)
  to_entries |
  map(select(.value.uses >= 2)) |
  sort_by(.value.success_rate) |

  if length > 0 then
    .[0] as $worst |
    if $worst.value.success_rate < 0.5 then
      "Avoid '\''\($worst.key)'\'' template (\($worst.value.success_rate * 100 | floor)% success). Prefer templates with >70% success rate."
    else
      "All templates performing adequately. Continue monitoring for patterns."
    end
  else
    "Insufficient data (need at least 2 uses per template)."
  end
')

# Build output JSON
output=$(jq -n \
  --argjson templates "$scores" \
  --arg recommendation "$recommendation" \
  '{
    generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    templates: $templates,
    recommendation: $recommendation
  }')

# Write to file (atomic write)
tmp_file=$(mktemp)
echo "$output" > "$tmp_file"
mv "$tmp_file" "$OUTPUT_FILE"

# Output results
if $OUTPUT_JSON; then
  # Machine-readable JSON
  cat "$OUTPUT_FILE"
else
  # Human-readable summary
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "TEMPLATE SCORING REPORT"
  echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  echo "$scores" | jq -r '
    to_entries | sort_by(-.value.uses) | .[] |
    "TEMPLATE: \(.key)",
    "  Uses:            \(.value.uses)",
    "  Success rate:    \((.value.success_rate * 100 | floor))%",
    "  Avg duration:    \(.value.avg_duration_s)s",
    "  Avg retries:     \(.value.avg_retries)",
    ""
  '

  echo "RECOMMENDATION"
  echo "  $recommendation"
  echo

  echo "Scores written to: $OUTPUT_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
