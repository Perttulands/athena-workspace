#!/usr/bin/env bash
# senate-deliberate.sh — Prototype Senate deliberation
#
# Usage: senate-deliberate.sh <case-file.json>
#
# Case file format:
# {
#   "id": "senate-001",
#   "type": "rule_evolution",
#   "summary": "Should rule X be amended?",
#   "evidence": ["path/to/file1", "path/to/file2"],
#   "question": "The specific question to deliberate"
# }
#
# This is a prototype — real implementation will use Relay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$WORKSPACE_ROOT/state/senate"
mkdir -p "$STATE_DIR/cases" "$STATE_DIR/verdicts" "$STATE_DIR/transcripts"

usage() {
    echo "Usage: $0 <case-file.json>" >&2
    echo "       $0 --quick '<question>'" >&2
    exit 1
}

(( $# >= 1 )) || usage

# Quick mode: just a question, no case file
if [[ "$1" == "--quick" ]]; then
    CASE_ID="quick-$(date +%s)"
    QUESTION="${2:-}"
    [[ -n "$QUESTION" ]] || usage
    CASE_FILE="$STATE_DIR/cases/$CASE_ID.json"
    jq -n --arg id "$CASE_ID" --arg q "$QUESTION" \
        '{id: $id, type: "quick", summary: $q, evidence: [], question: $q}' > "$CASE_FILE"
else
    CASE_FILE="$1"
    [[ -f "$CASE_FILE" ]] || { echo "Case file not found: $CASE_FILE" >&2; exit 1; }
    CASE_ID="$(jq -r '.id' "$CASE_FILE")"
fi

QUESTION="$(jq -r '.question' "$CASE_FILE")"
EVIDENCE="$(jq -r '.evidence | join("\n")' "$CASE_FILE")"

echo "=== Senate Deliberation: $CASE_ID ==="
echo "Question: $QUESTION"
echo ""

# Three perspectives
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

    # Use sessions_spawn would be ideal, but for prototype, use claude CLI
    RESPONSE="$(echo "$PROMPT" | claude --print 2>/dev/null || echo "POSITION: abstain
REASONING: Failed to get response from agent.
CONCERNS: Agent unavailable.")"
    
    echo "$AGENT_NAME:"
    echo "$RESPONSE" | head -20
    echo ""
    POSITIONS+=("$AGENT_NAME: $RESPONSE")
done

# Synthesize verdict
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

# Save verdict
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
