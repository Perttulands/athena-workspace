# Planning Guide

**Purpose:** Decompose high-level goals into sequenced, executable task plans.

---

## Overview

The planner bridges strategy and execution. It takes a natural language goal (e.g., "Add user authentication with JWT") and produces a structured plan with:
- Task breakdown
- Template selection per task
- Dependency graph
- Estimated durations
- Parallelization groups

Plans are stored in `state/plans/` and validated against `state/schemas/plan.schema.json`.

---

## Commands

### Create a plan

```bash
planner.sh create "Add user authentication with JWT"
planner.sh create "Fix login bug and add session timeout" --repo /path/to/repo
```

**What it does:**
1. Parses goal into subtasks (split on "and", "then", "after")
2. Classifies each task by keywords (fix → bug-fix, add → feature, etc.)
3. Assigns templates based on classification
4. Estimates duration from `state/template-scores.json`
5. Detects dependencies (sequential by default)
6. Computes parallelization groups (topological sort)
7. Writes `state/plans/plan-<timestamp>-<pid>.json`

### List plans

```bash
planner.sh list
```

Shows all plans with status: `plan-123 [draft] - Add auth (3 tasks)`

### Show plan details

```bash
planner.sh show plan-123
```

Displays:
- Goal, status, created timestamp
- Task breakdown with dependencies
- Estimated total duration
- Parallelization groups

### Validate plan

```bash
planner.sh validate plan-123
```

Checks:
- Unique task IDs
- All `depends_on` references exist
- No circular dependencies
- Templates exist (warning only)

---

## Plan Structure

Example `state/plans/plan-abc123.json`:

```json
{
  "schema_version": 1,
  "plan_id": "plan-abc123",
  "goal": "Add user authentication with JWT",
  "created_at": "2026-02-12T20:00:00Z",
  "status": "draft",
  "tasks": [
    {
      "task_id": "task-1",
      "title": "Add JWT middleware",
      "template": "feature",
      "depends_on": [],
      "estimated_duration_s": 180,
      "description": "add jwt middleware"
    },
    {
      "task_id": "task-2",
      "title": "Add login endpoint",
      "template": "feature",
      "depends_on": ["task-1"],
      "estimated_duration_s": 180,
      "description": "add login endpoint"
    }
  ],
  "total_estimated_s": 360,
  "parallelizable_groups": [
    ["task-1"],
    ["task-2"]
  ]
}
```

---

## Task Classification

Keywords → Template mapping:

| Keywords | Template |
|----------|----------|
| fix, bug | bug-fix |
| add, create, implement, build, feature | feature |
| refactor, clean, reorganize | refactor |
| test, validate, verify | test |
| document, doc, write | docs |
| deploy, release, ship | deploy |
| (other) | custom |

---

## Dependency Detection

**Current:** Sequential dependencies (task-2 depends on task-1, task-3 on task-2, etc.)

**Future:** Parse "after X is done" patterns for explicit cross-task dependencies.

---

## Duration Estimation

Reads `state/template-scores.json` for historical `avg_duration_s` per template.

If no data exists, `estimated_duration_s` is `null`.

---

## Parallelization Groups

Topologically sorted tasks grouped by max dependency depth:

```
Level 0: [task-1]          # No dependencies
Level 1: [task-2, task-3]  # Both depend on task-1
Level 2: [task-4]          # Depends on task-2 or task-3
```

Tasks in the same level can run in parallel (using git worktrees).

---

## Integration with Orchestrator

The orchestrator (`scripts/orchestrator.sh`) will:
1. Read active plans
2. Pick next task from parallelizable group
3. Create worktree
4. Dispatch agent with appropriate template
5. Update plan status on completion

---

## Best Practices

1. **Write clear goals:** "Add X and then Y" is easier to parse than vague descriptions
2. **One plan per feature:** Don't create mega-plans spanning weeks of work
3. **Review before execution:** Use `planner.sh show <id>` to verify task breakdown
4. **Validate early:** Run `planner.sh validate <id>` to catch errors before dispatch

---

## Limitations

- Task extraction is keyword-based (not LLM-powered)
- Dependencies default to sequential (explicit "after X" parsing is TODO)
- No plan editing UI (edit JSON files manually for now)
- Templates must exist in `templates/` directory
