#!/bin/bash
set -euo pipefail

VLLM_MLX_PORT="${VLLM_MLX_PORT:-8080}"
VLLM_MLX_HOST="${VLLM_MLX_HOST:-127.0.0.1}"
VLLM_MLX_MODEL="${VLLM_MLX_MODEL:-mlx-community/gemma-4-26b-a4b-it-4bit}"
VLLM_MLX_MAX_TOKENS="${VLLM_MLX_MAX_TOKENS:-2048}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-$VLLM_MLX_MODEL}"
VLLM_MLX_LOG="${VLLM_MLX_LOG:-/tmp/vllm-mlx.log}"

VLLM_MLX_PID=""
CLEANED_UP=0

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return
    fi
    CLEANED_UP=1

    echo
    echo "Shutting down vLLM MLX..."
    if [ -n "$VLLM_MLX_PID" ]; then
        pkill -P "$VLLM_MLX_PID" 2>/dev/null || true
        kill "$VLLM_MLX_PID" 2>/dev/null || true
    fi
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
}

export_claude_vars() {
    export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-http://$VLLM_MLX_HOST:$VLLM_MLX_PORT}"
    export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-not-needed}"
    export CLAUDE_EFFORT="${CLAUDE_EFFORT:-low}"
    export CLAUDE_BARE="${CLAUDE_BARE:-0}"
    export CLAUDE_ADD_DIR="${CLAUDE_ADD_DIR:-$PWD}"
    export CLAUDE_TOOLS="${CLAUDE_TOOLS:-Read,Glob,Grep,LSP,Write,Edit,Bash,Monitor,EnterPlanMode,ExitPlanMode,AskUserQuestion}"
    export CLAUDE_APPEND_SYSTEM_PROMPT="${CLAUDE_APPEND_SYSTEM_PROMPT:-}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
    export MAX_THINKING_TOKENS="${MAX_THINKING_TOKENS:-0}"
}

select_tool_call_parser() {
    local model_name_lower
    model_name_lower=$(printf '%s' "$VLLM_MLX_MODEL" | tr '[:upper:]' '[:lower:]')

    case "$model_name_lower" in
        *gemma-4*|*gemma4*)
            printf 'gemma4\n'
            ;;
        *qwen3-coder*|*qwen3coder*)
            printf 'qwen3_coder\n'
            ;;
        *qwen*)
            printf 'qwen\n'
            ;;
        *llama*)
            printf 'llama\n'
            ;;
        *deepseek*)
            printf 'deepseek\n'
            ;;
        *mistral*)
            printf 'mistral\n'
            ;;
        *gpt-oss*)
            printf 'gpt-oss\n'
            ;;
        *minimax*)
            printf 'minimax\n'
            ;;
        *)
            printf 'auto\n'
            ;;
    esac
}

select_reasoning_parser() {
    local model_name_lower
    model_name_lower=$(printf '%s' "$VLLM_MLX_MODEL" | tr '[:upper:]' '[:lower:]')

    case "$model_name_lower" in
        *gemma-4*|*gemma4*)
            printf 'gemma4\n'
            ;;
        *qwen3*)
            printf 'qwen3\n'
            ;;
        *deepseek*r1*|*deepseek-r1*)
            printf 'deepseek_r1\n'
            ;;
        *gpt-oss*)
            printf 'gpt_oss\n'
            ;;
        *glm4*)
            printf 'glm4\n'
            ;;
        *)
            printf '\n'
            ;;
    esac
}

wait_for_port() {
    local port=$1
    local name=$2
    local pid=$3
    local log_file=$4

    printf "Waiting for %s on port %s" "$name" "$port"
    while ! lsof -i :"$port" >/dev/null 2>&1; do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo
            echo "ERROR: $name failed to start. Last log lines:"
            [ -f "$log_file" ] && tail -n 40 "$log_file"
            exit 1
        fi
        printf "."
        sleep 2
    done
    echo " ready"
}

trap cleanup EXIT
trap 'cleanup; exit 130' SIGINT
trap 'cleanup; exit 143' SIGTERM

require_command "vllm-mlx"
require_command "claude"

export_claude_vars

VLLM_MLX_TOOL_CALL_PARSER="${VLLM_MLX_TOOL_CALL_PARSER:-$(select_tool_call_parser)}"
VLLM_MLX_REASONING_PARSER="${VLLM_MLX_REASONING_PARSER:-$(select_reasoning_parser)}"

echo "Stopping any existing service on port $VLLM_MLX_PORT..."
lsof -ti :"$VLLM_MLX_PORT" | xargs kill -9 2>/dev/null || true
sleep 1

: > "$VLLM_MLX_LOG"

VLLM_MLX_ARGS=(
    serve "$VLLM_MLX_MODEL"
    --host "$VLLM_MLX_HOST"
    --port "$VLLM_MLX_PORT"
    --max-tokens "$VLLM_MLX_MAX_TOKENS"
    --served-model-name "$ANTHROPIC_MODEL"
    --enable-auto-tool-choice
    --tool-call-parser "$VLLM_MLX_TOOL_CALL_PARSER"
)

if [ -n "$VLLM_MLX_REASONING_PARSER" ]; then
    VLLM_MLX_ARGS+=(--reasoning-parser "$VLLM_MLX_REASONING_PARSER")
fi

vllm-mlx "${VLLM_MLX_ARGS[@]}" > "$VLLM_MLX_LOG" 2>&1 &
VLLM_MLX_PID=$!

wait_for_port "$VLLM_MLX_PORT" "vLLM MLX" "$VLLM_MLX_PID" "$VLLM_MLX_LOG"

cat <<EOF
vLLM MLX running.
  PID: $VLLM_MLX_PID
  Model: $VLLM_MLX_MODEL
  Max tokens: $VLLM_MLX_MAX_TOKENS
  Served model name: $ANTHROPIC_MODEL
  Tool parser: $VLLM_MLX_TOOL_CALL_PARSER
  Reasoning parser: ${VLLM_MLX_REASONING_PARSER:-disabled}
  Base URL: $ANTHROPIC_BASE_URL
  Claude effort: $CLAUDE_EFFORT
  Claude bare mode: $CLAUDE_BARE
  Claude add-dir: $CLAUDE_ADD_DIR
  Claude tools: $CLAUDE_TOOLS
  Claude append prompt: ${CLAUDE_APPEND_SYSTEM_PROMPT:+set}
  MAX_THINKING_TOKENS: $MAX_THINKING_TOKENS
  Log: $VLLM_MLX_LOG

EOF

CLAUDE_ARGS=(
    --model "$ANTHROPIC_MODEL"
    --effort "$CLAUDE_EFFORT"
    --add-dir "$CLAUDE_ADD_DIR"
    --tools "$CLAUDE_TOOLS"
)
if [[ "$CLAUDE_BARE" == "1" || "$CLAUDE_BARE" == "true" || "$CLAUDE_BARE" == "yes" ]]; then
    CLAUDE_ARGS+=(--bare)
fi
if [ -n "$CLAUDE_APPEND_SYSTEM_PROMPT" ]; then
    CLAUDE_ARGS+=(--append-system-prompt "$CLAUDE_APPEND_SYSTEM_PROMPT")
fi

claude "${CLAUDE_ARGS[@]}" "$@"
