#!/bin/bash

set -euo pipefail

# Cognee-focused MLX launcher.
# Runs a small OpenAI-compatible LLM endpoint plus a separate embeddings endpoint.

COGNEE_LLM_PORT="${COGNEE_LLM_PORT:-4100}"
COGNEE_EMBEDDING_PORT="${COGNEE_EMBEDDING_PORT:-4101}"

COGNEE_LLM_MODEL="${COGNEE_LLM_MODEL:-mlx-community/Qwen3-4B-4bit}"
COGNEE_EMBEDDING_MODEL="${COGNEE_EMBEDDING_MODEL:-mlx-community/Qwen3-Embedding-0.6B-mxfp8}"
COGNEE_EMBEDDING_DIMENSIONS="${COGNEE_EMBEDDING_DIMENSIONS:-1024}"

COGNEE_LLM_LOG="${COGNEE_LLM_LOG:-/tmp/cognee-mlx-llm.log}"
COGNEE_EMBEDDING_LOG="${COGNEE_EMBEDDING_LOG:-/tmp/cognee-mlx-embedding.log}"

LLM_PID=""
EMBEDDING_PID=""

cleanup() {
    echo
    echo "Shutting down Cognee MLX services..."
    if [ -n "$LLM_PID" ]; then
        pkill -P "$LLM_PID" 2>/dev/null || true
        kill "$LLM_PID" 2>/dev/null || true
    fi
    if [ -n "$EMBEDDING_PID" ]; then
        pkill -P "$EMBEDDING_PID" 2>/dev/null || true
        kill "$EMBEDDING_PID" 2>/dev/null || true
    fi
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        echo "Install dependencies with:" >&2
        echo "  pip install mlx-lm mlx-openai-server" >&2
        exit 1
    fi
}

wait_for_port() {
    local port=$1
    local name=$2
    local pid=$3
    local log_file=$4

    printf "Waiting for %s on port %s" "$name" "$port"
    while ! lsof -i :"$port" >/dev/null 2>&1; do
        if ! kill -0 "$pid" 2>/dev/null; then
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

export_cognee_vars() {
    export LLM_PROVIDER="custom"
    export LLM_MODEL="openai/$COGNEE_LLM_MODEL"
    export LLM_ENDPOINT="http://127.0.0.1:$COGNEE_LLM_PORT/v1"
    export LLM_API_KEY="."

    export EMBEDDING_PROVIDER="custom"
    export EMBEDDING_MODEL="$COGNEE_EMBEDDING_MODEL"
    export EMBEDDING_ENDPOINT="http://127.0.0.1:$COGNEE_EMBEDDING_PORT/v1"
    export EMBEDDING_API_KEY="."
    export EMBEDDING_DIMENSIONS="$COGNEE_EMBEDDING_DIMENSIONS"
}

print_cognee_vars() {
    cat <<EOF

Cognee environment:
  LLM_PROVIDER=$LLM_PROVIDER
  LLM_MODEL=$LLM_MODEL
  LLM_ENDPOINT=$LLM_ENDPOINT
  EMBEDDING_PROVIDER=$EMBEDDING_PROVIDER
  EMBEDDING_MODEL=$EMBEDDING_MODEL
  EMBEDDING_ENDPOINT=$EMBEDDING_ENDPOINT
  EMBEDDING_DIMENSIONS=$EMBEDDING_DIMENSIONS

Logs:
  LLM: $COGNEE_LLM_LOG
  Embeddings: $COGNEE_EMBEDDING_LOG

EOF
}

trap cleanup EXIT SIGINT SIGTERM

require_command "mlx_lm.server"
require_command "mlx-openai-server"

echo "Stopping any previous Cognee MLX services on ports $COGNEE_LLM_PORT and $COGNEE_EMBEDDING_PORT..."
lsof -ti :"$COGNEE_LLM_PORT" | xargs kill -9 2>/dev/null || true
lsof -ti :"$COGNEE_EMBEDDING_PORT" | xargs kill -9 2>/dev/null || true
sleep 1

export_cognee_vars

echo "Starting Cognee LLM: $COGNEE_LLM_MODEL"
mlx_lm.server \
    --model "$COGNEE_LLM_MODEL" \
    --port "$COGNEE_LLM_PORT" \
    --temp 0.0 \
    --max-tokens 2048 \
    --use-default-chat-template \
    --prefill-step-size 2048 \
    --prompt-cache-size 8 \
    --prompt-cache-bytes 2GB \
    > "$COGNEE_LLM_LOG" 2>&1 &
LLM_PID=$!

wait_for_port "$COGNEE_LLM_PORT" "Cognee LLM" "$LLM_PID" "$COGNEE_LLM_LOG"

echo "Starting Cognee embeddings: $COGNEE_EMBEDDING_MODEL"
mlx-openai-server launch \
    --model-type embeddings \
    --model-path "$COGNEE_EMBEDDING_MODEL" \
    --port "$COGNEE_EMBEDDING_PORT" \
    --host 127.0.0.1 \
    --no-log-file \
    > "$COGNEE_EMBEDDING_LOG" 2>&1 &
EMBEDDING_PID=$!

wait_for_port "$COGNEE_EMBEDDING_PORT" "Cognee embeddings" "$EMBEDDING_PID" "$COGNEE_EMBEDDING_LOG"

print_cognee_vars

if [ "$#" -gt 0 ]; then
    "$@"
else
    echo "Services are running. Press Ctrl-C to stop."
    wait
fi
