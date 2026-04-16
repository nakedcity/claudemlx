# claudemlx 🚀

A high-performance local inference bridge to run [Claude CLI](https://github.com/anthropics/claude-code) with local MLX models on Apple Silicon.

This project transforms your Mac into a local "Sonnet-class" workspace by proxying the Claude CLI through LiteLLM to an optimized MLX server.

## ✨ Features
- **Performance Optimized**: Fine-tuned for M-series hardware with **Prompt Caching** and **Greedy Decoding** for instant, reliable code generation.
- **Seamless Integration**: Uses a standard `local-model` alias to bypass Claude CLI authentication headaches and satisfy strict naming requirements.
- **Robust Lifecycle**: Automatically handles cleanup of background processes and manages port synchronization.
- **Direct Output**: Specially configured system prompts suppress internal model "reasoning" blocks for a clean, direct UI experience.

## 🛠️ Stack
- **Inference**: [MLX-LM](https://github.com/ml-explore/mlx-llm) (Optimized for Apple Silicon).
- **Proxy**: [LiteLLM](https://github.com/BerriAI/litellm) (Protocol translation from Anthropic to local OpenAI).
- **Client**: [Claude Code CLI](https://github.com/anthropics/claude-code).

## 🚀 Getting Started

### Requirements
- Apple Silicon Mac (M1/M2/M3/M4/M5).
- Python 3.10+.
- `pip install mlx-lm litellm`.
- `npm install -g @anthropic-ai/claude-code`.

### Usage
1.  **Clone and Enter**:
    ```bash
    git clone https://github.com/nakedcity/claudemlx.git
    cd claudemlx
    chmod +x claudemlx.sh
    ```
2.  **Launch**:
    ```bash
    ./claudemlx.sh
    ```
    The script will start the MLX server, initialize the LiteLLM proxy, and launch the Claude CLI connected to your local model.

### ⚙️ Configuration
The system is currently pre-configured for **Gemma-2-26B**, providing a balance of high intelligence and local speed. You can easily swap models by editing the `MLX_MODEL` variable in `claudemlx.sh`.

```bash
export MLX_MODEL="mlx-community/gemma-4-26b-a4b-it-4bit"
```

## 📜 Professional History
This project provides a clean, single-commit history representing the finalized, stable implementation of the local Claude bridge.
