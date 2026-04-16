#!/bin/bash
# Configuration
MLX_PORT=8080
export MLX_BASE_URL="http://0.0.0.0:$MLX_PORT/v1"
LITELLM_PROXY_PORT=4000 # claude-code-proxy default

export MLX_MODEL="mlx-community/gemma-4-26b-a4b-it-4bit"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Cleanup function to kill background processes on exit
cleanup() {
    echo -e "\n🛑 Shutting down services..."
    [ -n "$MLX_PID" ] && kill $MLX_PID 2>/dev/null
    [ -n "$LITELLM_PID" ] && kill $LITELLM_PID 2>/dev/null
    exit
}

# Trap signals for cleanup
trap cleanup EXIT SIGINT SIGTERM

# Helper to wait for a port to become active with process health monitoring
wait_for_port() {
    local port=$1
    local name=$2
    local pid=$3
    local log_file=$4
    
    echo -n "⏳ Waiting for $name on port $port..."
    while ! lsof -i :$port >/dev/null 2>&1; do
        # Check if the background process is still alive
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo -e "\n❌ ERROR: $name (PID $pid) failed to start!"
            echo "-------------------------- LOGS --------------------------"
            [ -f "$log_file" ] && tail -n 20 "$log_file" || echo "Log file $log_file not found."
            echo "----------------------------------------------------------"
            exit 1
        fi
        echo -n "."
        sleep 2
    done
    echo " Ready! ✅"
}

echo "🧹 Cleaning up existing processes on ports $MLX_PORT and $LITELLM_PROXY_PORT..."
lsof -ti :$MLX_PORT | xargs kill -9 2>/dev/null
lsof -ti :$LITELLM_PROXY_PORT | xargs kill -9 2>/dev/null
sleep 1

# Using greedy decoding and prompt capping to prevent OOM
mlx_lm.server --model "$MLX_MODEL" --port $MLX_PORT \
    --temp 0.0 --max-tokens 2048 \
    --use-default-chat-template \
    --prompt-cache-size 16 --prompt-cache-bytes 12GB \
    > /tmp/mlx.log 2>&1 &
MLX_PID=$!

wait_for_port $MLX_PORT "MLX Server" "$MLX_PID" "/tmp/mlx.log"

export ANTHROPIC_BASE_URL="http://0.0.0.0:$LITELLM_PROXY_PORT"
export ANTHROPIC_API_KEY="dummy-key"
export ANTHROPIC_AUTH_TOKEN="dummy-token"
export OPENAI_API_KEY="sk-key"
export LITELLM_MODEL="hyperbolic/$MLX_MODEL"
litellm --config "$SCRIPT_DIR/config.yaml" > /tmp/litellm.log 2>&1 & 
LITELLM_PID=$!

wait_for_port $LITELLM_PROXY_PORT "LiteLLM Proxy" "$LITELLM_PID" "/tmp/litellm.log"

echo "✨ Services running. PIDs: MLX ($MLX_PID), LiteLLM ($LITELLM_PID)"

claude --model "local-model"
