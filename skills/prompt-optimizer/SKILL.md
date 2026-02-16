---
name: prompt-optimizer
description: Analyzes run history from state/runs/ and suggests improvements to prompt templates in templates/. Identifies failure patterns, high retry rates, and weak prompts. Use when optimizing agent performance, improving templates, or analyzing swarm effectiveness.
---

# Prompt Optimizer

Analyzes `state/runs/*.json` to find weak prompts and improve templates.

```bash
./skills/prompt-optimizer/optimize-prompts.sh                    # Analyze all
./skills/prompt-optimizer/optimize-prompts.sh --template feature # Specific template
./skills/prompt-optimizer/optimize-prompts.sh --ab-test feature  # Generate variant
./skills/prompt-optimizer/optimize-prompts.sh --json             # JSON output
```

## What It Detects

- **High retry rates** — unclear constraints, missing context
- **Timeout patterns** — scope too large, needs decomposition
- **Incomplete work** — vague acceptance criteria
- **Variable issues** — empty/malformed template variables

## Output

Per-template: success rate, avg duration, retry rate, failure reasons, and specific recommendations (section, before/after, rationale).

## A/B Testing

`--ab-test <template>` creates `templates/<name>-v2.md` alongside the original. Dispatch 50/50, compare success rates.
