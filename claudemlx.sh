#!/bin/bash
# Configuration

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Cleanup function to kill background processes on exit
cleanup() {
    echo -e "\n🛑 Shutting down services..."
    # Kill the background loop subshell and its spawned server
    if [ -n "$MLX_PID" ]; then
        pkill -P "$MLX_PID" 2>/dev/null
        kill "$MLX_PID" 2>/dev/null
    fi
    [ -n "$LLM_PID" ] && kill "$LLM_PID" 2>/dev/null
    exit
}

export_global_vars() {
    
    export MLX_PORT=8080
    export MLX_BASE_URL="http://0.0.0.0:$MLX_PORT/v1"
    # export MLX_MODEL="mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"
    # export MLX_MODEL="mlx-community/Devstral-Small-2505-4bit"
    # So far best results model for agentic coding tasks locally m5 48GB in my experience
    export MLX_MODEL="mlx-community/gemma-4-26b-a4b-it-4bit"

    # LiteLLM config but also use for cognee
    # see https://docs.cognee.ai/setup-configuration/llm-providers
    export LLM_PROVIDER="custom"
    # I see openrouter for compatibility with openai was the best option [I tried few more]
    export LLM_MODEL="openrouter/$MLX_MODEL"
    export LLM_API_KEY=""
    export LLM_PORT=4000 # claude-code-proxy default
    export LLM_ENDPOINT="http://0.0.0.0:$LLM_PORT"
    
    # Override for anthropic and openai for litellm
    echo "OpenAI and Anthropic auth keys will be set to dummy values."
    export ANTHROPIC_BASE_URL="http://0.0.0.0:$LLM_PORT"
    export ANTHROPIC_API_KEY="dummy-key"
    export ANTHROPIC_AUTH_TOKEN="dummy-token"
    export OPENAI_API_KEY="sk-key"
    export ANTHROPIC_MODEL="local-model"
}
# Trap signals for cleanup
trap cleanup EXIT SIGINT SIGTERM
export_global_vars
 
# Server wrapper with auto-restart
run_mlx_server() {
    while true; do
        echo "[$(date +'%H:%M:%S')] 🚀 Starting MLX Server..." >> /tmp/mlx.log
        mlx_lm.server --model "$MLX_MODEL" --port $MLX_PORT \
            --temp 0.0 --max-tokens 2048 \
            --use-default-chat-template \
            --prefill-step-size 4096 \
            --prompt-cache-size 32 --prompt-cache-bytes 16GB \
            >> /tmp/mlx.log 2>&1
        echo "[$(date +'%H:%M:%S')] ⚠️ MLX Server crashed. Restarting in 2s..." >> /tmp/mlx.log
        sleep 2
    done
}

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

echo "🧹 Cleaning up existing processes on ports $MLX_PORT and $LLM_PORT..."
lsof -ti :$MLX_PORT | xargs kill -9 2>/dev/null
lsof -ti :$LLM_PORT | xargs kill -9 2>/dev/null
sleep 1

# Using greedy decoding and prompt capping for performance
# Optimized for Devstral agentic reliability
run_mlx_server &
MLX_PID=$!

wait_for_port $MLX_PORT "MLX Server" "$MLX_PID" "/tmp/mlx.log"


litellm --config "$SCRIPT_DIR/config.yaml" > /tmp/litellm.log 2>&1 & 
LLM_PID=$!

wait_for_port $LLM_PORT "LiteLLM Proxy" "$LLM_PID" "/tmp/litellm.log"

echo "✨ Services running. PIDs: MLX ($MLX_PID), LiteLLM ($LLM_PID)"

claude
