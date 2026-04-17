#!/bin/bash
set -euo pipefail

# Stability-first local Claude Code -> LiteLLM -> MLX launcher.
# Values can be overridden from the environment, e.g.:
#   MLX_MODEL="mlx-community/gemma-4-26b-a4b-it-4bit" ./claudemlx.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MLX_PID=""
LLM_PID=""
CLEANED_UP=0

MLX_LOG="${MLX_LOG:-/tmp/mlx.log}"
LITELLM_LOG="${LITELLM_LOG:-/tmp/litellm.log}"

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return
    fi
    CLEANED_UP=1

    echo
    echo "Shutting down services..."
    if [ -n "$MLX_PID" ]; then
        pkill -P "$MLX_PID" 2>/dev/null || true
        kill "$MLX_PID" 2>/dev/null || true
    fi
    if [ -n "$LLM_PID" ]; then
        pkill -P "$LLM_PID" 2>/dev/null || true
        kill "$LLM_PID" 2>/dev/null || true
    fi
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        echo "Install or expose it with uv, for example:" >&2
        echo "  uv tool install mlx-lm" >&2
        echo "  uv tool install litellm" >&2
        echo "  npm install -g @anthropic-ai/claude-code" >&2
        exit 1
    fi
}

export_global_vars() {
    export MLX_PORT="${MLX_PORT:-8080}"
    export MLX_HOST="${MLX_HOST:-127.0.0.1}"
    export MLX_BASE_URL="${MLX_BASE_URL:-http://127.0.0.1:$MLX_PORT/v1}"

    # Override MLX_MODEL to experiment with other locally cached MLX models.
    export MLX_MODEL="${MLX_MODEL:-mlx-community/gemma-2-9b-it-4bit}"

    export MLX_MAX_TOKENS="${MLX_MAX_TOKENS:-2048}"
    export MLX_TEMP="${MLX_TEMP:-0.0}"
    export MLX_PROMPT_CONCURRENCY="${MLX_PROMPT_CONCURRENCY:-1}"
    export MLX_DECODE_CONCURRENCY="${MLX_DECODE_CONCURRENCY:-1}"

    # Qwen3.5 hybrid attention/Mamba models have shown cache-shape crashes in
    # MLX-LM server mode. Keep them single-flight and disable prompt caching.
    if [[ "$MLX_MODEL" == *Qwen3.5* || "$MLX_MODEL" == *qwen3_5* || "$MLX_MODEL" == *qwen3-5* ]]; then
        export MLX_PREFILL_STEP_SIZE="${MLX_PREFILL_STEP_SIZE:-512}"
        export MLX_PROMPT_CACHE_SIZE="${MLX_PROMPT_CACHE_SIZE:-0}"
        export MLX_PROMPT_CACHE_BYTES="${MLX_PROMPT_CACHE_BYTES:-0GB}"
    else
        export MLX_PREFILL_STEP_SIZE="${MLX_PREFILL_STEP_SIZE:-1024}"
        export MLX_PROMPT_CACHE_SIZE="${MLX_PROMPT_CACHE_SIZE:-2}"
        export MLX_PROMPT_CACHE_BYTES="${MLX_PROMPT_CACHE_BYTES:-2GB}"
    fi

    export LLM_PROVIDER="${LLM_PROVIDER:-custom}"
    # Keep openrouter here. In this local Claude Code bridge, switching this to
    # openai can make LiteLLM/Claude auth routing fail.
    export LLM_MODEL="${LLM_MODEL:-openrouter/$MLX_MODEL}"
    export LLM_API_KEY="${LLM_API_KEY:-}"
    export LLM_PORT="${LLM_PORT:-4000}"
    export LLM_ENDPOINT="${LLM_ENDPOINT:-http://127.0.0.1:$LLM_PORT/v1}"

    export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-http://127.0.0.1:$LLM_PORT}"
    export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-dummy-key}"
    export ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-dummy-token}"
    export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-key}"
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-local-model}"

    # Global Claude settings on this machine currently request high effort.
    # For local MLX, low effort is much faster and avoids unnecessary thinking.
    export CLAUDE_EFFORT="${CLAUDE_EFFORT:-low}"
    export CLAUDE_BARE="${CLAUDE_BARE:-1}"
    export CLAUDE_ADD_DIR="${CLAUDE_ADD_DIR:-$PWD}"
    export CLAUDE_TOOLS="${CLAUDE_TOOLS:-default}"
    export CLAUDE_APPEND_SYSTEM_PROMPT="${CLAUDE_APPEND_SYSTEM_PROMPT:-}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
}

run_mlx_server() {
    while true; do
        echo "[$(date +'%H:%M:%S')] Starting MLX server: $MLX_MODEL" >> "$MLX_LOG"
        status=0
        mlx_lm.server --model "$MLX_MODEL" --host "$MLX_HOST" --port "$MLX_PORT" \
            --temp "$MLX_TEMP" --max-tokens "$MLX_MAX_TOKENS" \
            --use-default-chat-template \
            --prefill-step-size "$MLX_PREFILL_STEP_SIZE" \
            --prompt-concurrency "$MLX_PROMPT_CONCURRENCY" \
            --decode-concurrency "$MLX_DECODE_CONCURRENCY" \
            --prompt-cache-size "$MLX_PROMPT_CACHE_SIZE" \
            --prompt-cache-bytes "$MLX_PROMPT_CACHE_BYTES" \
            >> "$MLX_LOG" 2>&1 || status=$?
        echo "[$(date +'%H:%M:%S')] MLX server exited with status $status. Restarting in 2s..." >> "$MLX_LOG"
        sleep 2
    done
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

require_command "mlx_lm.server"
require_command "litellm"
require_command "claude"

export_global_vars

echo "Stopping existing services on ports $MLX_PORT and $LLM_PORT..."
lsof -ti :"$MLX_PORT" | xargs kill -9 2>/dev/null || true
lsof -ti :"$LLM_PORT" | xargs kill -9 2>/dev/null || true
sleep 1

: > "$MLX_LOG"
: > "$LITELLM_LOG"

run_mlx_server &
MLX_PID=$!
wait_for_port "$MLX_PORT" "MLX Server" "$MLX_PID" "$MLX_LOG"

litellm --config "$SCRIPT_DIR/config.yaml" > "$LITELLM_LOG" 2>&1 &
LLM_PID=$!
wait_for_port "$LLM_PORT" "LiteLLM Proxy" "$LLM_PID" "$LITELLM_LOG"

cat <<EOF
Services running.
  MLX PID: $MLX_PID
  LiteLLM PID: $LLM_PID
  MLX model: $MLX_MODEL
  LiteLLM model: $LLM_MODEL
  MLX cache: $MLX_PROMPT_CACHE_SIZE entries / $MLX_PROMPT_CACHE_BYTES
  MLX concurrency: prompt=$MLX_PROMPT_CONCURRENCY decode=$MLX_DECODE_CONCURRENCY
  Claude effort: $CLAUDE_EFFORT
  Claude bare mode: $CLAUDE_BARE
  Claude add-dir: $CLAUDE_ADD_DIR
  Claude tools: $CLAUDE_TOOLS
  Claude append prompt: ${CLAUDE_APPEND_SYSTEM_PROMPT:+set}
  Logs: $MLX_LOG and $LITELLM_LOG

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
