# Claude Agent SDK with Local LLMs via MoonBit Gateway

Run Claude Code and the Claude Agent SDK against local models served by [Ollama](https://ollama.com), using the MoonBit LLM Gateway as a protocol translator.

## Architecture

### Anthropic Messages API (Claude Code / Agent SDK)

```
Claude Agent SDK (Node.js)
  │  model: "sonnet" (→ claude-sonnet-4-6)
  │  ANTHROPIC_BASE_URL=http://localhost:18080
  ▼
MoonBit LLM Gateway (--dialect anthropic)
  │  POST /v1/messages  ← Anthropic Messages API
  │  modelAliases: claude-sonnet-4-6 → llama3
  │  transform: Anthropic → OpenAI Chat Completions
  ▼
Ollama (http://localhost:11434/v1)
  │  POST /v1/chat/completions  ← OpenAI-compatible
  │  model: llama3
  ▼
Response (OpenAI → Anthropic, returned to SDK)
```

### Responses API (OpenAI Agents SDK compatible)

```
Client (fetch / OpenAI SDK)
  │  POST /v1/responses  ← Responses API
  ▼
MoonBit LLM Gateway (--dialect openai)
  │  harmony pipeline: Responses API → Chat Completions
  ▼
Ollama (http://localhost:11434/v1)
  │  POST /v1/chat/completions
  ▼
Response (Chat Completions → Responses API, returned to client)
```

## Setup

```bash
# Install Ollama and pull a model
ollama pull llama3

# Install Node.js dependencies
cd examples/claude-agent-sdk
npm install
```

## Usage

### 1. Start the gateway

For Claude Code / Agent SDK (Anthropic dialect):

```bash
cd cmd/gateway-native
moon run --target native . -- \
  --dialect anthropic \
  --config ../../examples/claude-agent-sdk/gateway-config.json
```

For Responses API (OpenAI dialect):

```bash
moon run --target native . -- \
  --dialect openai \
  --config ../../examples/claude-agent-sdk/gateway-config.json
```

### 2a. Claude Agent SDK

```bash
ANTHROPIC_BASE_URL=http://localhost:18080 \
ANTHROPIC_AUTH_TOKEN=dummy \
node src/agent-sdk.mjs "Explain quicksort in 3 sentences."
```

### 2b. Claude Code CLI

```bash
ANTHROPIC_BASE_URL=http://localhost:18080 \
ANTHROPIC_AUTH_TOKEN=dummy \
claude --model sonnet --print "What is 2+2?"
```

### 2c. Anthropic SDK (direct)

```bash
node src/anthropic-sdk.mjs
```

### 2d. Responses API

```bash
node src/responses-api.mjs llama3
```

## How It Works

### Model Aliasing

Claude Agent SDK / Claude Code CLI only accepts Claude model names internally.
The gateway's `modelAliases` config rewrites the model name before forwarding:

```json
{
  "modelAliases": {
    "claude-sonnet-4-6": "llama3"
  }
}
```

SDK sends `claude-sonnet-4-6` → gateway rewrites to `llama3` → Ollama serves the request.

### Protocol Translation

The gateway translates between three API surfaces:

| Surface | Endpoint | Use case |
|---------|----------|----------|
| Anthropic Messages | `POST /v1/messages` | Claude Code, Agent SDK |
| OpenAI Chat Completions | `POST /v1/chat/completions` | OpenAI SDK, general LLM clients |
| OpenAI Responses API | `POST /v1/responses` | OpenAI Agents SDK (harmony pipeline) |

Any surface can route to any backend (OpenAI, Ollama, Anthropic, Gemini, etc.).

### Authentication

- `ANTHROPIC_AUTH_TOKEN=dummy` — passes the CLI/SDK auth check (gateway ignores it)
- Ollama requires no API key by default

## Notes

- Use `ANTHROPIC_AUTH_TOKEN`, not `ANTHROPIC_API_KEY` (avoids OAuth taking precedence)
- The CLI sends `/v1/messages?beta=true` — the gateway handles query parameters
- Tool usage (Bash, Read, Edit, etc.) depends on the backend model's capabilities
- Responses API currently supports non-streaming only (streaming infrastructure exists)
