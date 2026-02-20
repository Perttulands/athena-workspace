#!/usr/bin/env bash
# senate-deliberate.sh — Senate case filing + deliberation prototype

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$WORKSPACE_ROOT/state/senate"
OUTBOX_FILE="$STATE_DIR/outbox/case-filed.jsonl"
mkdir -p "$STATE_DIR/cases" "$STATE_DIR/verdicts" "$STATE_DIR/transcripts" "$(dirname "$OUTBOX_FILE")"

RELAY_BIN="${SENATE_RELAY_BIN:-$HOME/go/bin/relay}"
RELAY_TO="${SENATE_RELAY_TO:-senate}"
RELAY_FROM="${SENATE_RELAY_FROM:-athena}"

usage() {
    cat >&2 <<USAGE
Usage:
  $0 <case-file.json>
  $0 --quick "<question>"
  $0 --file-case <case-file.json> [--to <agent>] [--from <agent>]
  $0 --file-case --quick "<question>" [--to <agent>] [--from <agent>]
USAGE
    exit 1
}

file_case_via_relay() {
    local case_file="$1"
    local payload=""
    payload="$(jq -cn \
        --arg type "senate.case.filed" \
        --arg filed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg from "$RELAY_FROM" \
        --slurpfile case "$case_file" \
        '{type:$type, filed_at:$filed_at, from:$from, case_id:$case[0].id, case:$case[0]}')" || payload=""

    [[ -n "$payload" ]] || {
        echo "failed to build Relay payload" >&2
        return 1
    }

    if [[ -x "$RELAY_BIN" ]] && "$RELAY_BIN" send "$RELAY_TO" "$payload" --agent "$RELAY_FROM" --thread "$(jq -r '.id' "$case_file")" --priority high --tag "senate,case,filed" >/dev/null 2>&1; then
        echo "Filed case via Relay: $(jq -r '.id' "$case_file") -> $RELAY_TO"
        return 0
    fi

    printf '%s\n' "$payload" >> "$OUTBOX_FILE"
    echo "Relay unavailable, queued case filing in $OUTBOX_FILE" >&2
}

FILE_ONLY=false
QUICK_QUESTION=""
INPUT_CASE_FILE=""

(( $# >= 1 )) || usage
while (( $# > 0 )); do
    case "$1" in
        --quick)
            QUICK_QUESTION="${2:-}"
            [[ -n "$QUICK_QUESTION" ]] || usage
            shift 2
            ;;
        --file-case)
            FILE_ONLY=true
            shift
            ;;
        --to)
            RELAY_TO="${2:-}"
            [[ -n "$RELAY_TO" ]] || usage
            shift 2
            ;;
        --from)
            RELAY_FROM="${2:-}"
            [[ -n "$RELAY_FROM" ]] || usage
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            [[ -z "$INPUT_CASE_FILE" ]] || usage
            INPUT_CASE_FILE="$1"
            shift
            ;;
    esac
done

if [[ -n "$QUICK_QUESTION" ]]; then
    CASE_ID="quick-$(date +%s)"
    CASE_FILE="$STATE_DIR/cases/$CASE_ID.json"
    jq -n --arg id "$CASE_ID" --arg q "$QUICK_QUESTION" \
        '{id: $id, type: "quick", summary: $q, evidence: [], question: $q}' > "$CASE_FILE"
else
    [[ -n "$INPUT_CASE_FILE" ]] || usage
    [[ -f "$INPUT_CASE_FILE" ]] || {
        echo "Case file not found: $INPUT_CASE_FILE" >&2
        exit 1
    }
    CASE_ID="$(jq -r '.id // empty' "$INPUT_CASE_FILE")"
    [[ -n "$CASE_ID" ]] || CASE_ID="senate-$(date +%s)"
    CASE_FILE="$STATE_DIR/cases/$CASE_ID.json"
    jq --arg id "$CASE_ID" \
        '.id = $id | .type = (.type // "general") | .summary = (.summary // .question // "") | .evidence = (.evidence // [])' \
        "$INPUT_CASE_FILE" > "$CASE_FILE"
fi

QUESTION="$(jq -r '.question // empty' "$CASE_FILE")"
[[ -n "$QUESTION" ]] || {
    echo "Case file must include a non-empty .question: $CASE_FILE" >&2
    exit 1
}

if [[ "$FILE_ONLY" == "true" ]]; then
    file_case_via_relay "$CASE_FILE"
    exit 0
fi

EVIDENCE="$(jq -r '.evidence | join("\n")' "$CASE_FILE")"

echo "=== Senate Deliberation: $CASE_ID ==="
echo "Question: $QUESTION"
echo ""

PERSPECTIVES=(
    "You are a PRAGMATIST. Prioritize what works, what ships, what reduces friction. Be skeptical of theoretical purity."
    "You are a PURIST. Prioritize correctness, consistency, and long-term maintainability. Be skeptical of shortcuts."
    "You are a SKEPTIC. Challenge assumptions. Look for edge cases. Ask 'what could go wrong?' Be the devil's advocate."
)

POSITIONS=()
for i in 0 1 2; do
    PERSPECTIVE="${PERSPECTIVES[$i]}"
    AGENT_NAME="Agent-$((i+1))"
    echo "--- $AGENT_NAME deliberating ---"

    PROMPT="$PERSPECTIVE

You are participating in a Senate deliberation. Read the case and provide your position.

CASE ID: $CASE_ID
QUESTION: $QUESTION

Evidence files (if any): $EVIDENCE

Provide your position in this format:
POSITION: [approve/reject/amend]
REASONING: [2-3 sentences explaining your position]
CONCERNS: [any concerns or caveats]

Be concise. This is deliberation, not an essay."

    RESPONSE="$(echo "$PROMPT" | claude --print 2>/dev/null || echo "POSITION: abstain
REASONING: Failed to get response from agent.
CONCERNS: Agent unavailable.")"

    echo "$AGENT_NAME:"
    echo "$RESPONSE" | head -20
    echo ""
    POSITIONS+=("$AGENT_NAME: $RESPONSE")
done

echo "=== Synthesizing Verdict ==="
SYNTHESIS_PROMPT="You are the Senate Judge. Review the positions from three agents and render a verdict.

CASE ID: $CASE_ID
QUESTION: $QUESTION

POSITIONS:
${POSITIONS[0]}

---
${POSITIONS[1]}

---
${POSITIONS[2]}

---

Synthesize a verdict:
1. Note areas of agreement
2. Note areas of disagreement
3. Render a VERDICT: [approve/reject/amend/defer]
4. Provide REASONING (incorporating the strongest arguments)
5. Note any DISSENT worth preserving

Be decisive. The verdict is binding."

VERDICT="$(echo "$SYNTHESIS_PROMPT" | claude --print 2>/dev/null || echo "VERDICT: defer
REASONING: Failed to synthesize verdict.
DISSENT: None")"

echo "$VERDICT"

VERDICT_FILE="$STATE_DIR/verdicts/$CASE_ID.json"
jq -n \
    --arg case_id "$CASE_ID" \
    --arg question "$QUESTION" \
    --arg verdict "$VERDICT" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
        case_id: $case_id,
        question: $question,
        verdict_text: $verdict,
        rendered_at: $timestamp
    }' > "$VERDICT_FILE"

echo ""
echo "=== Verdict saved to: $VERDICT_FILE ==="
