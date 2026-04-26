#!/bin/bash
set -euo pipefail

# --- Defaults ---
VLLM_MLX_PORT="${VLLM_MLX_PORT:-8080}"
VLLM_MLX_HOST="${VLLM_MLX_HOST:-127.0.0.1}"
VLLM_MLX_MODEL="${VLLM_MLX_MODEL:-mlx-community/Qwen3.6-35B-A3B-4bit}"
VLLM_MLX_MAX_TOKENS="${VLLM_MLX_MAX_TOKENS:-16384}"
VLLM_MLX_LOG="${VLLM_MLX_LOG:-/tmp/vllm-mlx.log}"
CLAUDE_EFFORT="${CLAUDE_EFFORT:-high}"
MAX_THINKING_TOKENS="${MAX_THINKING_TOKENS:-0}"

# --- Internal State ---
VLLM_MLX_PID=""
CLEANED_UP=0

# --- Functions ---

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- [claude-code args]]

Options:
  -m, --model MODEL        MLX model to use (default: $VLLM_MLX_MODEL)
  -p, --port PORT          Port for vLLM MLX (default: $VLLM_MLX_PORT)
  -t, --tokens TOKENS      Max tokens for vLLM MLX (default: $VLLM_MLX_MAX_TOKENS)
  -e, --effort EFFORT      Claude effort: low, medium, high (default: $CLAUDE_EFFORT)
  -l, --log FILE           Log file path (default: $VLLM_MLX_LOG)
  --thinking TOKENS        Max thinking tokens (default: $MAX_THINKING_TOKENS)
  --parser PARSER          Force a specific tool-call-parser
  --reasoning PARSER       Force a specific reasoning-parser
  --dry-run                Print commands without executing
  -h, --help               Show this help message

Environment variables (like VLLM_MLX_MODEL) are also respected and can be set in a .env file.
Any arguments after -- are passed directly to 'claude'.
EOF
}

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then return; fi
    CLEANED_UP=1
    echo -e "\nShutting down vLLM MLX..."
    if [ -n "$VLLM_MLX_PID" ]; then
        pkill -P "$VLLM_MLX_PID" 2>/dev/null || true
        kill "$VLLM_MLX_PID" 2>/dev/null || true
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

select_tool_call_parser() {
    local m; m=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$m" in
        *gemma-4*|*gemma4*) echo "gemma4" ;;
        *qwen3-coder*|*qwen3coder*) echo "qwen3_coder" ;;
        *qwen*) echo "qwen" ;;
        *llama*) echo "llama" ;;
        *deepseek*) echo "deepseek" ;;
        *mistral*) echo "mistral" ;;
        *gpt-oss*) echo "gpt-oss" ;;
        *minimax*) echo "minimax" ;;
        *) echo "auto" ;;
    esac
}

select_reasoning_parser() {
    local m; m=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$m" in
        *gemma-4*|*gemma4*) echo "gemma4" ;;
        *qwen3*) echo "qwen3" ;;
        *deepseek*r1*|*deepseek-r1*) echo "deepseek_r1" ;;
        *gpt-oss*) echo "gpt_oss" ;;
        *glm4*) echo "glm4" ;;
        *) echo "" ;;
    esac
}

wait_for_service() {
    local port=$1 pid=$2 log=$3
    printf "Waiting for vLLM MLX on port %s" "$port"
    for i in {1..60}; do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo -e "\nERROR: vLLM MLX died. Last log lines:"
            tail -n 20 "$log"; exit 1
        fi
        if curl -s "http://127.0.0.1:$port/v1/models" >/dev/null 2>&1; then
            echo " ready."
            return 0
        fi
        printf "."
        sleep 2
    done
    echo -e "\nERROR: Timeout waiting for service."
    exit 1
}

# --- Initialization ---

# Load .env if it exists
if [ -f .env ]; then
    echo "Loading environment from .env"
    export $(grep -v '^#' .env | xargs)
fi

DRY_RUN=0
VLLM_MLX_TOOL_CALL_PARSER="${VLLM_MLX_TOOL_CALL_PARSER:-}"
VLLM_MLX_REASONING_PARSER="${VLLM_MLX_REASONING_PARSER:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model) VLLM_MLX_MODEL="$2"; shift 2 ;;
        -p|--port) VLLM_MLX_PORT="$2"; shift 2 ;;
        -t|--tokens) VLLM_MLX_MAX_TOKENS="$2"; shift 2 ;;
        -e|--effort) CLAUDE_EFFORT="$2"; shift 2 ;;
        -l|--log) VLLM_MLX_LOG="$2"; shift 2 ;;
        --thinking) MAX_THINKING_TOKENS="$2"; shift 2 ;;
        --parser) VLLM_MLX_TOOL_CALL_PARSER="$2"; shift 2 ;;
        --reasoning) VLLM_MLX_REASONING_PARSER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) show_help; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

trap cleanup EXIT SIGINT SIGTERM

require_command "vllm-mlx"
require_command "claude"
require_command "curl"

# --- Configuration ---
export ANTHROPIC_BASE_URL="http://$VLLM_MLX_HOST:$VLLM_MLX_PORT"
export ANTHROPIC_API_KEY="not-needed"
export ANTHROPIC_MODEL="$VLLM_MLX_MODEL"
export CLAUDE_ADD_DIR="${CLAUDE_ADD_DIR:-$PWD}"
export CLAUDE_TOOLS="Agent,Read,Write,Edit,Glob,Grep,Bash,Monitor,LSP,EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree,AskUserQuestion,TaskCreate,TaskUpdate,TaskList,TaskGet,TaskOutput,TaskStop,Skill,WebFetch,WebSearch,NotebookEdit,CronCreate,CronDelete,CronList"
export CLAUDE_APPEND_SYSTEM_PROMPT="${CLAUDE_APPEND_SYSTEM_PROMPT:-Do not use the Agent tool or spawn subagents. Work directly by reading files, searching code, and writing results yourself. Do not say what you are going to do, just do it.}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export MAX_THINKING_TOKENS

TOOL_PARSER="${VLLM_MLX_TOOL_CALL_PARSER:-$(select_tool_call_parser "$VLLM_MLX_MODEL")}"
REASON_PARSER="${VLLM_MLX_REASONING_PARSER:-$(select_reasoning_parser "$VLLM_MLX_MODEL")}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run - commands that would be executed:"
    echo "vllm-mlx serve $VLLM_MLX_MODEL --host $VLLM_MLX_HOST --port $VLLM_MLX_PORT --max-tokens $VLLM_MLX_MAX_TOKENS --served-model-name $ANTHROPIC_MODEL --enable-auto-tool-choice --tool-call-parser $TOOL_PARSER ${REASON_PARSER:+--reasoning-parser $REASON_PARSER}"
    echo "claude --model $ANTHROPIC_MODEL --effort $CLAUDE_EFFORT --add-dir $CLAUDE_ADD_DIR --tools $CLAUDE_TOOLS --append-system-prompt '...' $@"
    exit 0
fi

# --- Execution ---
echo "Stopping existing service on port $VLLM_MLX_PORT..."
lsof -ti :"$VLLM_MLX_PORT" | xargs kill -9 2>/dev/null || true

: > "$VLLM_MLX_LOG"

VLLM_ARGS=(
    serve "$VLLM_MLX_MODEL"
    --host "$VLLM_MLX_HOST"
    --port "$VLLM_MLX_PORT"
    --max-tokens "$VLLM_MLX_MAX_TOKENS"
    --served-model-name "$ANTHROPIC_MODEL"
    --enable-auto-tool-choice
    --tool-call-parser "$TOOL_PARSER"
)
[ -z "$REASON_PARSER" ] || VLLM_ARGS+=(--reasoning-parser "$REASON_PARSER")

vllm-mlx "${VLLM_ARGS[@]}" > "$VLLM_MLX_LOG" 2>&1 &
VLLM_MLX_PID=$!

wait_for_service "$VLLM_MLX_PORT" "$VLLM_MLX_PID" "$VLLM_MLX_LOG"

cat <<EOF
vLLM MLX: $VLLM_MLX_MODEL (Port: $VLLM_MLX_PORT, Parser: $TOOL_PARSER)
Claude:   Effort: $CLAUDE_EFFORT, Max Thinking: $MAX_THINKING_TOKENS
Logs:     $VLLM_MLX_LOG

EOF

CLAUDE_ARGS=(
    --model "$ANTHROPIC_MODEL"
    --effort "$CLAUDE_EFFORT"
    --add-dir "$CLAUDE_ADD_DIR"
    --tools "$CLAUDE_TOOLS"
)
[ -z "$CLAUDE_APPEND_SYSTEM_PROMPT" ] || CLAUDE_ARGS+=(--append-system-prompt "$CLAUDE_APPEND_SYSTEM_PROMPT")

claude "${CLAUDE_ARGS[@]}" "$@"
