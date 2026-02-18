# Documentation Gardener

**Systematic documentation quality auditor for OpenClaw workspace and athena-web projects**

## Quick Start

```bash
# Audit workspace documentation
./skills/doc-gardener/doc-gardener.sh --workspace

# Audit athena-web project
./skills/doc-gardener/doc-gardener.sh --athena-web

# Focus on specific aspects
./skills/doc-gardener/doc-gardener.sh --workspace --type readme --focus examples

# Generate JSON for scripting
./skills/doc-gardener/doc-gardener.sh --workspace --format json > audit.json
```

## What It Does

The documentation gardener performs comprehensive audits of:

- **README files**: Project documentation, setup guides, usage instructions
- **SKILL.md files**: Agent skill documentation in the OpenClaw workspace
- **Inline code comments**: Comments in shell scripts, JavaScript, Python, Rust
- **JSDoc comments**: Function/API documentation in JavaScript/TypeScript
- **API documentation**: REST endpoint docs, request/response schemas

## Quality Assessment

Each document is scored (0-10) across five dimensions:

1. **Clarity**: Is it easy to understand? Well-organized? Good formatting?
2. **Completeness**: Is all essential information present? Edge cases covered?
3. **Examples**: Are there working code examples? Do they cover key scenarios?
4. **Consistency**: Terminology consistent? Style uniform? Matches code?
5. **Technical Accuracy**: Is information correct? Up-to-date? Precise?

## Output

### Human-Readable Report

```
╔══════════════════════════════════════════════════════════════╗
║           Documentation Audit Report                        ║
╚══════════════════════════════════════════════════════════════╝

Audit ID: da-20260213-143022-workspace
Target: $HOME/athena
Date: 2026-02-13T14:30:22Z
Documents Reviewed: 23

Overall Score: 7.5/10

━━━ Summary ━━━
Documentation is generally clear but lacks examples in several areas.
SKILL.md files are well-structured. Inline comments need improvement.

━━━ Files Reviewed ━━━
✓ README.md (8/10)
✓ skills/code-review/SKILL.md (9/10)
⚠ scripts/orchestrator.sh (6/10) - 3 issue(s)

━━━ Major Issues (2) ━━━
• scripts/orchestrator.sh:45: [completeness] No error handling explanation
  → Add comments explaining error recovery strategy

━━━ Improvement Priorities ━━━
1. [high] Add examples to skills/prompt-optimizer/SKILL.md
   Impact: Users can't understand how to use the skill effectively
   Effort: 1-2 hours
```

### JSON Output

Structured data perfect for:
- CI/CD pipelines
- Quality gates
- Automated remediation
- Trend tracking

```bash
./skills/doc-gardener/doc-gardener.sh --workspace --format json | \
  jq '.improvement_priorities[] | select(.priority == "high")'
```

## Common Use Cases

### Pre-Release Quality Check

```bash
# Before a release, ensure docs are ready
./skills/doc-gardener/doc-gardener.sh --workspace
# Fix major issues, then verify
./skills/doc-gardener/doc-gardener.sh --workspace | grep "Overall Score"
```

### Focus on Missing Examples

```bash
# Find documentation that lacks code examples
./skills/doc-gardener/doc-gardener.sh --workspace --focus examples --format json | \
  jq '.findings[] | select(.category == "examples") | .file' | sort -u
```

### API Documentation Audit

```bash
# Audit only API docs in athena-web
./skills/doc-gardener/doc-gardener.sh --athena-web --type api-docs
```

### Quick Check with Haiku

```bash
# Fast spot-check before committing
./skills/doc-gardener/doc-gardener.sh --workspace --model haiku --type inline-comments
```

### Integration with Athena

```bash
# In orchestrator.sh or overnight workflows
DOC_SCORE=$(./skills/doc-gardener/doc-gardener.sh --workspace --format json | jq -r '.overall_score')

if (( $(echo "$DOC_SCORE < 7.0" | bc -l) )); then
    echo "Documentation quality below threshold, creating remediation task"
    # Create bead to fix documentation issues
fi
```

## Understanding Severity Levels

- **major**: Critical gaps that block users. Fix immediately.
  - Example: Missing installation instructions in README
  - Example: Incorrect API endpoint documented

- **minor**: Reduces effectiveness but not blocking.
  - Example: Unclear explanation of a parameter
  - Example: Missing edge case documentation

- **suggestion**: Nice-to-have improvements.
  - Example: Could add more examples
  - Example: Consider adding diagrams

## Calibration

If the agent produces false positives, teach it:

```bash
# View the audit
cat state/doc-audits/da-20260213-143022-workspace.json | jq '.findings[7]'

# If finding #7 is wrong, reject it
./skills/doc-gardener/doc-gardener.sh --calibrate reject \
  --audit-id da-20260213-143022-workspace \
  --finding-id 7
```

Rejected findings are stored in `state/calibration/doc-gardener.jsonl` and help improve future audits.

## Exit Codes

- **0**: Audit completed successfully (score >= 5.0)
- **1**: Audit failed (invalid args, missing dependencies)
- **2**: Documentation quality critically low (score < 5.0)

## Tips

1. **Run regularly**: Weekly or before releases
2. **Start focused**: Use `--type` and `--focus` to tackle specific issues
3. **Prioritize impact**: Fix high-priority items from `improvement_priorities` first
4. **Track trends**: Compare scores over time
5. **Calibrate**: Reject false positives to train the agent
6. **Automate**: Add to CI/CD or overnight orchestration

## Advanced Usage

### Audit Specific Files

```bash
# Create a minimal project directory with symlinks to specific files
mkdir /tmp/audit-target
ln -s ~/workspace/skills/new-skill/SKILL.md /tmp/audit-target/
./skills/doc-gardener/doc-gardener.sh --path /tmp/audit-target
```

### Combine with Code Review

```bash
# After code review, check if documentation was updated
./scripts/review-agent.sh bd-123
if [ $? -eq 0 ]; then
    ./skills/doc-gardener/doc-gardener.sh --workspace --type inline-comments
fi
```

### Track Improvements Over Time

```bash
# Monthly audit
./skills/doc-gardener/doc-gardener.sh --workspace --format json > \
  state/doc-audits/monthly-$(date +%Y-%m).json

# Compare scores
jq -r '.overall_score' state/doc-audits/monthly-2026-*.json
```

## Dependencies

- `bash` 4.0+
- `jq` (JSON processing)
- `find`, `grep`, `sed`, `bc` (standard UNIX tools)
- `claude` CLI (for AI analysis)

## Files Created

- `state/doc-audits/<audit-id>.json` - Audit results
- `state/calibration/doc-gardener.jsonl` - Feedback data

## Related

- `skills/code-review/` - Code quality review agent
- `skills/prompt-optimizer/` - Prompt quality optimization
- `scripts/review-agent.sh` - Git commit review wrapper

## Contributing

To improve the doc-gardener:

1. **Add new quality dimensions**: Edit the prompt template in `doc-gardener.sh`
2. **Improve metrics**: Enhance the metrics calculation logic
3. **Add document types**: Extend `find_docs()` function
4. **Better formatting**: Improve `generate_human_report()` output

## Future Enhancements

- [ ] Spell-check integration
- [ ] Link validation (detect broken URLs)
- [ ] Diagram/visualization detection
- [ ] Integration with Vale prose linter
- [ ] Automated PR creation for fixes
- [ ] Historical trending dashboard
- [ ] Slack notifications for low scores
- [ ] Glossary consistency checking
