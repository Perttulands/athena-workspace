# shellcheck shell=bash
# config.sh — Read agent configuration from config/agents.json
# Source this file; do not execute directly.

if [[ -v CONFIG_FILE ]]; then
    CONFIG_FILE="${CONFIG_FILE:?CONFIG_FILE cannot be empty}"
else
    CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/agents.json"
fi

require_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: config/agents.json not found at $CONFIG_FILE" >&2
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi
}

# Get a value from agents.json. Usage: config_get '.claude.default_model'
config_get() {
    require_config
    jq -r "$1 // empty" "$CONFIG_FILE"
}

# Get the default model for an agent type. Usage: agent_default_model claude
agent_default_model() {
    config_get ".${1}.default_model"
}

# Resolve a model alias to full name. Usage: resolve_model claude opus → claude-opus-4-6
resolve_model() {
    local agent="$1" alias="$2"
    local full
    full=$(config_get ".${agent}.models.\"${alias}\"")
    if [[ -n "$full" ]]; then
        echo "$full"
    else
        # Not an alias — return as-is (might be a full model name)
        echo "$alias"
    fi
}

# Validate agent type exists in config
validate_agent_type() {
    local agent="$1"
    local exists
    exists=$(config_get ".${agent}.command")
    if [[ -z "$exists" ]]; then
        echo "Error: unknown agent type '$agent'" >&2
        echo "  Valid agents: $(config_get '[keys[]] | join(", ")')" >&2
        return 1
    fi
}

# Build the full command array for an agent. Sets AGENT_CMD array and MODEL variable.
# Usage: build_agent_cmd claude opus
#   → AGENT_CMD=(claude --dangerously-skip-permissions --model opus --mcp-config ...)
#   → MODEL=opus
build_agent_cmd() {
    local agent="$1"
    local model_input="${2:-}"
    require_config

    validate_agent_type "$agent" || return 1

    # Resolve model: explicit > default from config
    if [[ -z "$model_input" ]]; then
        model_input=$(agent_default_model "$agent")
        if [[ -z "$model_input" ]]; then
            echo "Error: no model specified and no default for '$agent' in config/agents.json" >&2
            return 1
        fi
        echo "INFO: Using default model for $agent: $model_input" >&2
    fi

    MODEL="$model_input"
    local full_model
    full_model=$(resolve_model "$agent" "$model_input")

    case "$agent" in
        claude)
            local cmd model_flag
            cmd=$(config_get '.claude.command')
            model_flag=$(config_get '.claude.agent_mode.model_flag')
            AGENT_CMD=("$cmd")

            # Agent mode flags (NOT print mode — agents need tool access)
            local claude_flags
            if ! claude_flags="$(config_get '[.claude.agent_mode.flags[]] | .[]')"; then
                echo "Warning: failed to read claude flags from config, using safe defaults" >&2
                claude_flags=$'-p\n--dangerously-skip-permissions'
            fi
            while IFS= read -r flag; do
                AGENT_CMD+=("$flag")
            done <<< "$claude_flags"

            AGENT_CMD+=("$model_flag" "$full_model")

            # MCP config for Agent Mail coordination
            local mcp_config
            mcp_config=$(config_get '.claude.mcp_config // empty')
            if [[ -n "$mcp_config" && -f "$mcp_config" ]]; then
                AGENT_CMD+=("--mcp-config" "$mcp_config")
            fi
            ;;
        codex)
            local cmd subcommand model_flag
            cmd=$(config_get '.codex.command')
            subcommand=$(config_get '.codex.subcommand')
            model_flag=$(config_get '.codex.exec_mode.model_flag')
            AGENT_CMD=("$cmd" "$subcommand" "$model_flag" "$full_model" "--yolo")

            if [[ -n "${DISPATCH_CODEX_REASONING_EFFORT:-}" ]]; then
                AGENT_CMD+=("-c" "model_reasoning_effort=\"$DISPATCH_CODEX_REASONING_EFFORT\"")
            fi
            ;;
        *)
            echo "Error: no command builder for agent type '$agent'" >&2
            return 1
            ;;
    esac
}
