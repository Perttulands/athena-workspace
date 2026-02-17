# Code Review Agent Skill

This skill provides automated code review capabilities for the agentic coding swarm.

## Quick Start

```bash
# Review a bead's changes
./scripts/review-agent.sh bd-123

# Check the exit code
echo $?  # 0=accept, 1=reject, 2=revise

# View the results
cat state/reviews/bd-123.json
```

## What It Does

The code review agent:
1. Extracts the diff for a given bead ID
2. Evaluates code quality against Linus-inspired standards
3. Produces structured JSON output with verdict, score, and issues
4. Returns exit code based on verdict (for scripting)

## Output

Results are written to `state/reviews/<bead-id>.json`:

```json
{
  "bead": "bd-123",
  "verdict": "accept",
  "score": 8,
  "summary": "Clean implementation following repository patterns...",
  "issues": [],
  "patterns": [
    "Good: Used existing error handling patterns",
    "Good: Atomic commit with focused changes"
  ],
  "reviewed_at": "2026-02-12T20:45:00Z"
}
```

## Integration Points

### Post-Commit Hook

Add to agent completion workflow:

```bash
if ./scripts/review-agent.sh "$BEAD_ID"; then
    echo "Review passed"
    bd update "$BEAD_ID" --status done
else
    echo "Review failed - see state/reviews/$BEAD_ID.json"
fi
```

### Pre-Merge Gate

Block merges on reject:

```bash
./scripts/review-agent.sh "$BEAD_ID"
case $? in
    0) git merge "bead-$BEAD_ID" ;;
    2) echo "Needs revision - check review" ;;
    1) echo "Rejected - do not merge" ;;
esac
```

## Quality Standards

The agent checks:
- **Correctness**: Logic, error handling, edge cases
- **Test Quality**: Coverage, real vs mocked code, proper structure
- **Naming**: Clarity, consistency, conventions
- **Complexity**: Simplicity, nesting depth, abstraction level
- **Architecture**: Pattern adherence, data structure design

## Model Selection

- Default: `sonnet` (fast, accurate)
- For complex architectural reviews, modify the script to use `opus`

## Files

- `skills/code-review/SKILL.md` - Skill definition
- `templates/code-review.md` - Review prompt template
- `scripts/review-agent.sh` - Wrapper script
- `state/reviews/` - Review results (JSON)
