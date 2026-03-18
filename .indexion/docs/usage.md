## Usage

### Dialects

The gateway exposes different API surfaces depending on the `--dialect` flag:

| Dialect | Incoming API | Typical client | Description |
|---------|-------------|----------------|-------------|
| `anthropic` | Anthropic Messages (`POST /v1/messages`) | Claude Code, Claude Agent SDK | Translates Anthropic Messages API to OpenAI Chat Completions for the backend |
| `openai` | OpenAI Responses (`POST /v1/responses`) | OpenAI Agents SDK, Codex CLI | Harmony pipeline: Responses API to Chat Completions |
| `gemini` | Gemini-compatible | Gemini SDK clients | Translates Gemini requests to Chat Completions |
| `codex` | OpenAI Responses (`POST /v1/responses`) | Codex CLI | Responses API proxy optimized for Codex CLI tool-call flows |

All dialects forward to any OpenAI-compatible backend (Ollama, vLLM, OpenAI, etc.).

### Gateway configuration

The gateway is configured with a JSON file passed via `--config` (or `-c`).

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "modelsFromEndpoint": false,
      "modelPatterns": ["llama", "claude-"],
      "modelAliases": {
        "claude-sonnet-4-6": "llama3"
      },
      "models": [
        {
          "id": "llama3",
          "name": "Llama 3",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": 8192,
          "maxTokens": 4096
        }
      ]
    }
  },
  "server": {
    "port": 18080,
    "host": "0.0.0.0"
  }
}
```

#### Provider fields

| Field | Type | Description |
|-------|------|-------------|
| `baseUrl` | string | Backend API base URL (must expose `/v1/chat/completions`) |
| `api` | string | Backend API type (e.g. `"openai-completions"`) |
| `modelsFromEndpoint` | bool | Whether to fetch available models from the backend's `/v1/models` endpoint |
| `modelPatterns` | string[] | Glob patterns for model names this provider handles |
| `modelAliases` | object | Rewrites incoming model names before forwarding (e.g. map Claude model names to local model names) |
| `models` | object[] | Explicit model definitions with `id`, `name`, `reasoning`, `input`, `contextWindow`, `maxTokens` |

#### Server fields

| Field | Type | Description |
|-------|------|-------------|
| `port` | number | Port the gateway listens on |
| `host` | string | Bind address (e.g. `"0.0.0.0"` for all interfaces, `"127.0.0.1"` for localhost only) |

### Example: Claude Code + Ollama

Use the `anthropic` dialect so Claude Code's Anthropic Messages API calls are translated to Chat Completions for Ollama. Model aliasing maps Claude model names to local model names.

See [examples/claude-agent-sdk/](examples/claude-agent-sdk/) for the full setup.

```bash
# 1. Pull a model
ollama pull llama3

# 2. Start the gateway with anthropic dialect
cd cmd/gateway-native
moon run --target native . -- \
  --dialect anthropic \
  --config ../../examples/claude-agent-sdk/gateway-config.json

# 3. Run Claude Code against the local gateway
ANTHROPIC_BASE_URL=http://localhost:18080 \
ANTHROPIC_AUTH_TOKEN=dummy \
claude --model sonnet --print "What is 2+2?"
```

`ANTHROPIC_AUTH_TOKEN=dummy` satisfies the CLI's auth check; the gateway ignores it. Use `ANTHROPIC_AUTH_TOKEN` (not `ANTHROPIC_API_KEY`) to avoid OAuth taking precedence.

### Example: Codex CLI + Ollama

Use the gateway as a Responses API proxy so Codex CLI can talk to Ollama. No model aliasing is needed since Codex lets you specify any model name.

See [examples/codex/](examples/codex/) for the full setup, including a `run.sh` one-liner.

```bash
# 1. Pull a model
ollama pull llama3

# 2. Start the gateway
cmd/gateway-native/_build/native/debug/build/llm_interop-gateway-native.exe \
  -c examples/codex/gateway-config.json

# 3. Run Codex CLI against the gateway
codex -m "llama3" \
  -c 'model_providers.gw.name="Gateway"' \
  -c 'model_providers.gw.base_url="http://localhost:18080/v1"' \
  -c 'model_provider="gw"' \
  exec "List the files in the current directory"
```

Codex CLI sends Responses API requests with function tools (e.g. `shell`). The gateway translates these to Chat Completions, and multi-turn tool use works end to end.
