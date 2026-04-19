# claudemlx

A local Claude Code bridge for Apple Silicon. This repository provides two distinct ways to run a local LLM (via MLX) as an OpenAI-compatible endpoint and connect it to the Claude Code CLI.

## Implementation Paths

There are two primary ways to run the bridge, depending on your needs:

### 1. Streamlined: `claude-cli.sh`
A lightweight, single-process launcher using `vllm-mlx`. It is designed for speed and simplicity.

- **Core Tech**: `vllm-mlx`
- **Best For**: Quick, direct access to a single model with minimal overhead.
- **Key Features**:
  - Automatic selection of tool-call and reasoning parsers based on the model name.
  - Direct forwarding of arguments to Claude Code.
  - Built-in cleanup of existing listeners on the target port.

### 2. Robust: `claude-proxy-cli.sh`
A stability-first, multi-process launcher using `mlx_lm.server` and `litellm`.

- **Core Tech**: `mlx_lm.server` + `litellm`
- **Best For**: A more stable, production-like environment with advanced routing and aliasing.
- **Key Features**:
  - **Model Aliasing**: Uses `config.yaml` to map multiple Claude-style names (e.g., `claude-opus-4-6`, `sonnet`) to your local MLX model.
  - **Stability-First**: Includes automatic configuration for models (like Qwen3.5) to prevent cache-related crashes.
  - **Process Management**: Manages both the MLX server and the LiteLLM proxy as background services.

---

## Requirements

- Apple Silicon Mac.
- Python 3.10+.
- `mlx_lm.server` (via `uv tool install mlx-lm`) or `vllm-mlx` (via `uv tool install vllm-mlx`) available on `PATH`.
- `litellm` (via `uv tool install litellm`) available on `PATH`.
- `claude` (via `npm install -g @anthropic-ai/claude-code`) available on `PATH`.

---

## Usage

### Using the Streamlined Path (`claude-cli.sh`)
```bash
chmod +x claude-cli.sh
./claude-cli.sh
```

### Using the Robust Path (`claude-proxy-cli.sh`)
```bash
chmod +x claude-proxy-cli.sh
./claude-proxy-cli.sh
```

Arguments passed to the scripts are forwarded to Claude Code.

---

## Configuration & Defaults

Both scripts use environment variables for configuration. You can override these inline when launching.

### Common Variables

| Variable | Default (Proxy) | Purpose |
| --- | --- | --- |
| `MLX_MODEL` | `mlx-community/gemma-4-26b-a4b-it-4bit` | The local MLX model to serve. |
| `MLX_PORT` | `8080` | The port for the MLX server. |
| `LLM_PORT` | `4000` | The port for the LiteLLM proxy. |
| `ANTHROPIC_MODEL` | `local-model` | The model name Claude Code requests. |
| `CLAUDE_EFFORT` | `low` | Claude Code effort setting. |
| `CLAUDE_BARE` | `1` | Adds `--bare` by default. |
| `CLAUDE_ADD_DIR` | `$PWD` | Directory passed to Claude Code with `--add-dir`. |

### Example Overrides

**Change the model:**
```bash
MLX_MODEL="mlx-community/Devstral-Small-2505-4bit" ./claudemlx.sh
```

**Change ports:**
```bash
MLX_PORT=8081 LLM_PORT=4001 ./claudemlx.sh
```

**Adjust Claude settings:**
```bash
CLAUDE_EFFORT=low CLAUDE_BARE=0 ./claudemlx.sh
```

---

## LiteLLM Model Aliases (Proxy Path Only)

The `config.yaml` in the robust path allows you to use various Claude-style names to refer to your local model:

- `local-model`
- `claude-opus-4-6`
- `claude-sonnet-4-6`
- `claude-haiku-4-5`
- `haiku`
- `sonnet`
- `opus`

Each alias uses the environment variables `LLM_MODEL`, `MLX_BASE_URL`, and `OPENAI_API_KEY` to route requests through LiteLLM to your local MLX server.

---

## Troubleshooting

- **No deployments available**: If Claude Code reports no deployments, check the logs:
  - `tail -n 120 /tmp/mlx.log`
  - `tail -n 120 /tmp/litellm.log`
- **Port conflicts**: Both scripts attempt to kill existing listeners on the target ports before starting. If you encounter issues, ensure no other processes are using the ports.
