#!/usr/bin/env bash
# optimize-prompts.sh - Analyze run history and suggest template improvements

set -euo pipefail

if [[ -v WORKSPACE ]]; then
  WORKSPACE="${WORKSPACE:?WORKSPACE cannot be empty}"
else
  WORKSPACE="$HOME/.openclaw/workspace"
fi
RUNS_DIR="$WORKSPACE/state/runs"
TEMPLATES_DIR="$WORKSPACE/templates"
AB_TEST_DIR="$TEMPLATES_DIR/.ab-tests"

# Parse arguments
MODE="report"
TEMPLATE_FILTER=""
OUTPUT_FORMAT="human"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      TEMPLATE_FILTER="$2"
      shift 2
      ;;
    --ab-test)
      MODE="ab-test"
      TEMPLATE_FILTER="$2"
      shift 2
      ;;
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --help)
      cat <<EOF
Usage: optimize-prompts.sh [OPTIONS]

Analyze run history and suggest template improvements.

Options:
  --template NAME     Analyze specific template (e.g., 'feature')
  --ab-test NAME      Generate A/B test variant for template
  --json              Output structured JSON instead of human-readable report
  --help              Show this help

Examples:
  # Analyze all templates
  optimize-prompts.sh

  # Analyze specific template
  optimize-prompts.sh --template feature

  # Generate A/B test variant
  optimize-prompts.sh --ab-test feature

  # Get JSON output
  optimize-prompts.sh --json
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Check dependencies
for cmd in jq bc; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    exit 1
  fi
done

# Ensure directories exist
if [[ ! -d "$RUNS_DIR" ]]; then
  echo "Error: Runs directory not found: $RUNS_DIR" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "Error: Templates directory not found: $TEMPLATES_DIR" >&2
  exit 1
fi

# Source pattern analyzer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/analyze-patterns.sh"

# Main analysis
case "$MODE" in
  report)
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      generate_json_report "$TEMPLATE_FILTER"
    else
      generate_human_report "$TEMPLATE_FILTER"
    fi
    ;;
  ab-test)
    if [[ -z "$TEMPLATE_FILTER" ]]; then
      echo "Error: --ab-test requires a template name" >&2
      exit 1
    fi
    generate_ab_test_variant "$TEMPLATE_FILTER"
    ;;
esac
