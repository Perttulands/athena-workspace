# Documentation Gardener - Quick Start

## 30-Second Start

```bash
# Audit your workspace
./skills/doc-gardener/doc-gardener.sh --workspace

# Audit athena-web project
./skills/doc-gardener/doc-gardener.sh --athena-web
```

## Common Commands

```bash
# Focus on specific documentation types
./skills/doc-gardener/doc-gardener.sh --workspace --type readme
./skills/doc-gardener/doc-gardener.sh --workspace --type skills
./skills/doc-gardener/doc-gardener.sh --athena-web --type api-docs

# Focus on specific quality aspects
./skills/doc-gardener/doc-gardener.sh --workspace --focus examples
./skills/doc-gardener/doc-gardener.sh --workspace --focus completeness

# Quick check with faster model
./skills/doc-gardener/doc-gardener.sh --workspace --model haiku

# Get JSON output for automation
./skills/doc-gardener/doc-gardener.sh --workspace --format json
```

## Understanding Output

### Score Ranges
- **9-10**: Excellent, publication-ready
- **7-8**: Good, minor improvements needed
- **5-6**: Acceptable, some significant gaps
- **3-4**: Poor, needs substantial work
- **1-2**: Critical, major rewrite required

### Severity Levels
- **major**: Blocking issue, fix immediately
- **minor**: Improves quality, fix when possible
- **suggestion**: Nice-to-have enhancement

## Quick Fixes

After running an audit:

1. Check high-priority improvements:
   ```bash
   cat state/doc-audits/*.json | jq '.improvement_priorities[] | select(.priority == "high")'
   ```

2. Find files with major issues:
   ```bash
   cat state/doc-audits/*.json | jq -r '.findings[] | select(.severity == "major") | .file' | sort -u
   ```

3. Focus on quick wins (low effort, high impact):
   ```bash
   cat state/doc-audits/*.json | jq '.improvement_priorities[] | select(.effort == "quick")'
   ```

## Integration Examples

### Daily Check (Alias)
```bash
# Add to ~/.bashrc
alias doc-check='~/athena/skills/doc-gardener/doc-gardener.sh --workspace'
```

### Pre-Commit Hook
```bash
cp skills/doc-gardener/examples/pre-commit-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### CI/CD Pipeline
```bash
# In your CI script
./skills/doc-gardener/doc-gardener.sh --workspace --format json > audit.json
SCORE=$(jq -r '.overall_score' audit.json)
if (( $(echo "$SCORE < 7.0" | bc -l) )); then
    echo "Documentation quality check failed"
    exit 1
fi
```

## Troubleshooting

**"No documents found"**
- Check that the path is correct
- Verify you're in the right directory

**"Claude execution failed"**
- Ensure `claude` CLI is installed: `which claude`
- Check you have API access

**Score seems wrong**
- Review the findings to understand what was flagged
- Use `--calibrate reject` to teach the agent about false positives

## Next Steps

1. Run your first audit
2. Review the findings in `state/doc-audits/`
3. Fix high-priority issues
4. Re-run to verify improvements
5. Set up automation (pre-commit hook or CI/CD)

For full documentation, see [SKILL.md](SKILL.md) and [README.md](README.md).
