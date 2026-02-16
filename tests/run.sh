#!/usr/bin/env bash
# tests/run.sh — Single entry point for all tests
#
# Usage:
#   ./tests/run.sh              Run all e2e tests
#   ./tests/run.sh --unit       Run centurion unit tests (pytest)
#   ./tests/run.sh --all        Run everything
#   ./tests/run.sh <test-file>  Run specific test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

MODE="e2e"
SPECIFIC_TEST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit) MODE="unit"; shift ;;
        --all)  MODE="all"; shift ;;
        --help|-h)
            head -6 "$0" | tail -5 | sed 's/^# //'
            exit 0
            ;;
        *)
            SPECIFIC_TEST="$1"; shift ;;
    esac
done

PASSED=0 FAILED=0 FAILED_NAMES=()

run_test() {
    local test_file="$1" name
    name="$(basename "$test_file" .sh)"
    if bash "$test_file"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
}

run_e2e() {
    echo -e "${BOLD}═══ E2E Tests ═══${NC}"
    echo ""
    if [[ -n "$SPECIFIC_TEST" ]]; then
        run_test "$SPECIFIC_TEST"
    else
        for f in "$SCRIPT_DIR"/e2e/test-*.sh; do
            [[ -f "$f" ]] && run_test "$f"
        done
    fi
}

run_unit() {
    echo -e "${BOLD}═══ Unit Tests (Centurion) ═══${NC}"
    echo ""
    if command -v pytest &>/dev/null; then
        if pytest "$SCRIPT_DIR/unit/" -q 2>&1; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_NAMES+=("centurion-pytest")
        fi
    else
        echo "⊘ SKIP: pytest not found"
    fi
}

case "$MODE" in
    e2e)  run_e2e ;;
    unit) run_unit ;;
    all)  run_e2e; echo ""; run_unit ;;
esac

echo ""
echo -e "${BOLD}═══ Results ═══${NC}"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
(( FAILED > 0 )) && echo -e "  ${RED}Failed: $FAILED${NC}" || echo "  Failed: 0"
if (( FAILED > 0 )); then
    echo ""
    echo -e "${RED}Failed:${NC}"
    for t in "${FAILED_NAMES[@]}"; do echo "  - $t"; done
    exit 1
fi
echo -e "\n${GREEN}All tests passed.${NC}"
