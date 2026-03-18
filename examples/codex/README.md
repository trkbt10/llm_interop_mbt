# Codex CLI with Local LLMs via MoonBit Gateway

Run [OpenAI Codex CLI](https://github.com/openai/codex) against local models served by [Ollama](https://ollama.com), using the MoonBit LLM Gateway as a Responses API proxy.

## Architecture

```
Codex CLI
  │  POST /v1/responses  (stream: true)
  │  model: "llama3"
  ▼
MoonBit LLM Gateway (:18080)
  │  Harmony pipeline: Responses API → Chat Completions
  │  Parameters: temperature, top_p, max_output_tokens → max_tokens
  │  Tools: function tools pass through, non-function tools filtered
  ▼
Ollama (http://localhost:11434/v1)
  │  POST /v1/chat/completions  (stream: true)
  │  model: llama3
  ▼
Response (Chat Completions SSE → Responses API SSE → Codex CLI)
```

## Setup

```bash
# 1. Install Ollama and pull a model
ollama pull llama3

# 2. Build the gateway
cd cmd/gateway-native
moon build --target native

# 3. Install Codex CLI (if not already)
npm install -g @openai/codex
```

## Usage

```bash
# Start gateway + run Codex in one step:
./examples/codex/run.sh "What is 2+2?"

# Or manually:

# Terminal 1: Start gateway
cmd/gateway-native/_build/native/debug/build/llm_interop-gateway-native.exe \
  -c examples/codex/gateway-config.json

# Terminal 2: Run Codex CLI
codex -m "llama3" \
  -c 'model_providers.gw.name="Gateway"' \
  -c 'model_providers.gw.base_url="http://localhost:18080/v1"' \
  -c 'model_provider="gw"' \
  exec "What is 2+2?"
```

## Tool Calls

Codex CLI sends its shell tool as a Responses API function tool. The gateway converts it to Chat Completions format and passes it to the backend. Multi-turn tool use works:

```bash
./examples/codex/run.sh "List the files in the current directory"
```

Codex CLI receives a `function_call` for `shell` → executes it locally → sends the result back → gateway translates the multi-turn conversation → backend responds with a summary.

## Configuration

`gateway-config.json` configures Ollama with `llama3`. To use a different model or backend:

- **Different Ollama model**: Change `models[].id` and `modelPatterns`
- **Remote API**: Change `baseUrl` and add `apiKey` with `${ENV_VAR}` syntax
- **Any OpenAI-compatible API**: Just change `baseUrl` and `apiKey`
