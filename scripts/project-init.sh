#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <project-path> [--force]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

PROJECT_PATH="$1"
FORCE="false"

if [[ $# -eq 2 ]]; then
    if [[ "$2" != "--force" ]]; then
        usage
        exit 1
    fi
    FORCE="true"
fi

if [[ "$PROJECT_PATH" != /* ]]; then
    PROJECT_PATH="$(cd "$(pwd)" && pwd)/$PROJECT_PATH"
fi

mkdir -p "$PROJECT_PATH"

write_file() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
    if [[ -e "$target" && "$FORCE" != "true" ]]; then
        echo "Error: file exists: $target (use --force to overwrite)" >&2
        exit 1
    fi
    cat > "$target"
}

write_file "$PROJECT_PATH/AGENTS.md" <<'EOF'
# AGENTS.md

## Mission
Deliver production-ready code with clear verification and scoped changes.

## Required Behavior
1. Follow the task acceptance criteria exactly.
2. Keep documentation in present tense; docs describe what IS.
3. Keep edits minimal and focused on the task.
4. Run project verification commands before completion.
5. Report completion with:
   - summary of edits
   - files changed
   - commands run and outcomes
   - open risks or blockers
EOF

write_file "$PROJECT_PATH/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Mission
Implement task-scoped changes that meet acceptance criteria and verification requirements.

## Required Behavior
1. Follow the same operational policy as `AGENTS.md`.
2. Keep docs in present tense; docs describe what IS.
3. Keep edits scoped and avoid unrelated churn.
4. Run required verification commands before marking complete.
5. Report summary, changed files, verification outcomes, and open risks.
EOF

write_file "$PROJECT_PATH/.codex/config.toml" <<'EOF'
model = "gpt-5.3-codex"
model_reasoning_effort = "high"

[profiles.swarm-agent]
model = "gpt-5.3-codex"
model_reasoning_effort = "high"
EOF

echo "project-init complete:"
echo "- $PROJECT_PATH/AGENTS.md"
echo "- $PROJECT_PATH/CLAUDE.md"
echo "- $PROJECT_PATH/.codex/config.toml"
