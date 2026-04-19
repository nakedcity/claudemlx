# claudemlx

A local Claude Code bridge for Apple Silicon. `claudemlx.sh` starts an MLX-LM OpenAI-compatible server, puts LiteLLM in front of it, and launches Claude Code against the local proxy.

## What It Runs

```text
Claude Code CLI
  -> LiteLLM proxy on http://127.0.0.1:4000
  -> MLX-LM server on http://127.0.0.1:8080/v1
  -> local MLX model
```

The default local model is:

```bash
mlx-community/gemma-4-26b-a4b-it-4bit
```

Claude Code is pointed at the LiteLLM proxy with `ANTHROPIC_BASE_URL`, and the Claude-visible model name defaults to `local-model`.

## Requirements

- Apple Silicon Mac.
- Python 3.10+.
- `mlx_lm.server` available on `PATH`.
- `litellm` available on `PATH`.
- `claude` available on `PATH`.

The launcher prints install hints if a command is missing:

```bash
uv tool install mlx-lm
uv tool install litellm
npm install -g @anthropic-ai/claude-code
```

## Usage

```bash
chmod +x claudemlx.sh
./claudemlx.sh
```

Arguments passed to `claudemlx.sh` are forwarded to Claude Code:

```bash
./claudemlx.sh "hello"
```

Before starting, the script stops existing listeners on the MLX and LiteLLM ports. It then truncates the log files, starts MLX-LM, waits for its port, starts LiteLLM, waits for its port, prints the active settings, and finally runs `claude`.

On exit, Ctrl-C, or SIGTERM, it cleans up the MLX and LiteLLM background processes.

## Defaults

| Variable | Default | Purpose |
| --- | --- | --- |
| `MLX_HOST` | `127.0.0.1` | MLX-LM bind host. |
| `MLX_PORT` | `8080` | MLX-LM port. |
| `MLX_BASE_URL` | `http://127.0.0.1:$MLX_PORT/v1` | OpenAI-compatible MLX endpoint used by LiteLLM. |
| `MLX_MODEL` | `mlx-community/gemma-4-26b-a4b-it-4bit` | Local MLX model to serve. |
| `MLX_MAX_TOKENS` | `2048` | MLX-LM generation limit. |
| `MLX_TEMP` | `0.0` | Greedy decoding by default. |
| `MLX_PROMPT_CONCURRENCY` | `1` | MLX prompt concurrency. |
| `MLX_DECODE_CONCURRENCY` | `1` | MLX decode concurrency. |
| `MLX_PREFILL_STEP_SIZE` | `1024` | MLX prefill step size for most models. |
| `MLX_PROMPT_CACHE_SIZE` | `2` | Prompt cache entries for most models. |
| `MLX_PROMPT_CACHE_BYTES` | `2GB` | Prompt cache memory for most models. |
| `LLM_PORT` | `4000` | LiteLLM proxy port. |
| `LLM_MODEL` | `openrouter/$MLX_MODEL` | Provider-qualified model name passed through LiteLLM. |
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:$LLM_PORT` | Claude Code API base URL. |
| `ANTHROPIC_MODEL` | `local-model` | Model name Claude Code requests. |
| `CLAUDE_EFFORT` | `low` | Claude Code effort setting. |
| `CLAUDE_BARE` | `1` | Adds `--bare` by default. |
| `CLAUDE_ADD_DIR` | current directory | Directory passed to Claude Code with `--add-dir`. |
| `CLAUDE_TOOLS` | `default` | Claude Code tools setting. |
| `MLX_LOG` | `/tmp/mlx.log` | MLX-LM log file. |
| `LITELLM_LOG` | `/tmp/litellm.log` | LiteLLM log file. |

Qwen3.5 model names get a safer cache profile automatically:

```bash
MLX_PREFILL_STEP_SIZE=512
MLX_PROMPT_CACHE_SIZE=0
MLX_PROMPT_CACHE_BYTES=0GB
```

This avoids cache-shape crashes seen with hybrid attention/Mamba Qwen3.5 models in MLX-LM server mode.

## Configuration

Override settings inline when launching:

```bash
MLX_MODEL="mlx-community/Devstral-Small-2505-4bit" ./claudemlx.sh
```

Use different ports:

```bash
MLX_PORT=8081 LLM_PORT=4001 ./claudemlx.sh
```

Change Claude Code options:

```bash
CLAUDE_EFFORT=low CLAUDE_BARE=0 CLAUDE_TOOLS=default ./claudemlx.sh
```

Append an extra system prompt:

```bash
CLAUDE_APPEND_SYSTEM_PROMPT="Answer directly and avoid hidden reasoning." ./claudemlx.sh
```

## LiteLLM Model Aliases

`config.yaml` maps multiple Claude-style names to the same local MLX deployment:

- `local-model`
- `claude-opus-4-6`
- `claude-sonnet-4-6`
- `claude-haiku-4-5`
- `claude-haiku-4-5-20251001`
- `haiku`
- `sonnet`
- `opus`

Each alias uses:

```yaml
model: os.environ/LLM_MODEL
api_base: os.environ/MLX_BASE_URL
api_key: os.environ/OPENAI_API_KEY
max_parallel_requests: 1
timeout: 600
```

LiteLLM is configured with `drop_params: true` and a `request_timeout` of `600`.

## Troubleshooting

If Claude Code reports that no deployments are available, check the LiteLLM and MLX logs:

```bash
tail -n 120 /tmp/litellm.log
tail -n 120 /tmp/mlx.log
```

That usually means the local MLX server rejected the request, LiteLLM marked the alias unavailable, and Claude Code retried against the cooled-down model group.

If a port is already in use, the launcher kills existing listeners on `MLX_PORT` and `LLM_PORT` before starting fresh services.
