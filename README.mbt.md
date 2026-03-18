# llm_interop

**LLM Gateway -- a protocol translation layer between AI developer tools and LLM backends, written in MoonBit.**

llm_interop translates between Anthropic Messages API, OpenAI Chat Completions API, and OpenAI Responses API, letting you route requests from any client to any backend. This means tools like Claude Code, OpenAI Codex CLI, and the Claude Agent SDK can run against local models (e.g., Ollama) or any OpenAI-compatible endpoint without modification.

- **Protocol bridging across three API surfaces** -- accepts Anthropic Messages, OpenAI Chat Completions, and OpenAI Responses API requests and translates them to whichever format the backend expects
- **Run AI developer tools against any backend** -- use Claude Code, Codex CLI, or the Claude Agent SDK with Ollama, OpenAI, Gemini, or any OpenAI-compatible API by simply changing the gateway config
- **Model aliasing and parameter harmonization** -- rewrites model names (e.g., `claude-sonnet-4-6` to `llama3`) and normalizes parameters like `max_output_tokens` to `max_tokens` so clients and backends speak the same language


## Architecture

The MoonBit LLM Gateway sits between AI-powered tools (Claude Code, OpenAI Agents SDK, Codex CLI, etc.) and LLM backends (OpenAI, Anthropic, Ollama, Gemini, etc.), translating protocols on the fly so that any client can talk to any backend.

### Architecture Diagram

```
AI Tool / Client                   MoonBit LLM Gateway                     LLM Backend
==================          ==============================          =======================

Claude Code / SDK  ----\
  POST /v1/messages     |
                        |    +----------------------------+
OpenAI Agents SDK  -----|    |        GatewaySurface      |
  POST /v1/responses    |--->|  (Anthropic|OpenAI|Gemini  |
                        |    |           |Codex)          |
Codex CLI / VS Code ----|    +------------+---------------+
  JSON-RPC stdio        |                 |
                        |    +------------v---------------+
MCP Client  -----------/     |     Dialect Transforms     |
  MCP stdio                  |  Anthropic <-> OpenAI      |
                             |  Gemini    <-> OpenAI      |
                             |  Responses -> Completions  |
                             |  (harmony pipeline)        |
                             +------------+---------------+
                                          |
                             +------------v---------------+
                             |   Model Aliasing + Routing |
                             |  claude-sonnet-4-6 -> llama3 |
                             +------------+---------------+
                                          |
                              +-----------+-----------+
                              |           |           |
                              v           v           v
                           OpenAI     Anthropic    Ollama
                           Gemini     Bedrock      Codex
                           Copilot    claude mcp   ...
```

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Dialect** | A `GatewaySurface` (OpenAI, Anthropic, Gemini, Codex) that determines which inbound API the gateway exposes. Each surface routes incoming requests to the appropriate transform pipeline. The `DialectSpec` struct binds a `ModelApi` to its endpoint paths, auth headers, and surface type. |
| **Harmony pipeline** | The Responses API compatibility layer. Converts OpenAI Responses API requests (`POST /v1/responses`) into Chat Completions calls, then maps the response back -- enabling any Chat Completions backend to serve Responses API clients (e.g. OpenAI Agents SDK). |
| **Model aliasing** | Per-provider `model_aliases` map that rewrites incoming model names before forwarding. Lets Claude Code send `claude-sonnet-4-6` while the gateway routes it to `llama3` on Ollama, or any other backend model. Configured in `gateway-config.json`. |
| **SSE streaming** | Server-Sent Events parser and serializer for streaming LLM responses. Each dialect has its own stream accumulator that incrementally builds the final response from SSE chunks, handling protocol-specific delta formats (Anthropic `content_block_delta`, OpenAI `choices[].delta`, etc.). |

### Project Structure

```
llm_interop/
├── src/                              Library packages
│   ├── gateway/                      Core gateway: config, types, dialect dispatch, routing
│   ├── dialects/                     Protocol transform implementations
│   │   ├── anthropic/                Anthropic Messages API transforms and accumulator
│   │   ├── openai/                   OpenAI Chat Completions + Responses API transforms
│   │   ├── gemini/                   Google Gemini GenerativeAI transforms
│   │   ├── harmony/                  Harmony (gpt-oss) Chat Completions accumulator
│   │   ├── codex/                    Codex app-server JSON-RPC transforms
│   │   └── claude_mcp/              `claude mcp serve` subprocess transforms
│   ├── types/                        Shared message types (ToolCallRequest, etc.)
│   ├── client/                       HTTP client with multi-provider integration tests
│   ├── sse/                          SSE parser (JSONL) and serializer
│   ├── jsonrpc/                      JSON-RPC 2.0 pure protocol layer
│   ├── mcp/                          MCP (Model Context Protocol) pure protocol layer
│   ├── spawn/                        Shell-safe command builder for subprocess execution
│   ├── interop/                      Fixture-based protocol interop tests
│   │   └── util/                     Test utilities
│   ├── utils/                        JSON manipulation and string helpers
│   └── wasm-gc/                      WebAssembly (wasm-gc) build artifacts
│       └── release/                  Release binaries
├── cmd/                              Executable entry points
│   ├── gateway-native/               HTTP gateway server (native target)
│   ├── app-server/                   Codex app-server frontend (JSON-RPC over stdio)
│   ├── claude-mcp-server/            MCP server frontend (emulates `claude mcp serve`)
│   └── js-test-demo/                 JS target test/demo runner
└── examples/                         Usage examples and integration guides
```


# Getting Started

## Quick Start

### Prerequisites

- **MoonBit toolchain** -- install from <https://www.moonbitlang.com/download/>
- **Ollama** -- install from <https://ollama.com> and pull a model:

```bash
ollama pull llama3
```

### Build the gateway

```bash
cd cmd/gateway-native
moon build --target native
```

### Run: Claude Code through the gateway to Ollama

**Terminal 1 -- start the gateway:**

```bash
cd cmd/gateway-native
moon run --target native . -- \
  --dialect anthropic \
  --config ../../examples/claude-agent-sdk/gateway-config.json
```

**Terminal 2 -- run Claude Code CLI:**

```bash
ANTHROPIC_BASE_URL=http://localhost:18080 \
ANTHROPIC_AUTH_TOKEN=dummy \
claude --model sonnet --print "What is 2+2?"
```

The gateway intercepts the Anthropic Messages API request from Claude Code, rewrites the model name (e.g. `claude-sonnet-4-6` to `llama3`) via the config's `modelAliases`, translates the request to OpenAI Chat Completions format, and forwards it to Ollama. The response is translated back so Claude Code sees a normal Anthropic API reply powered by your local model.


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


## Packages

llm_interop provides dialect adapters for multiple LLM API surfaces. Any inbound surface can route to any backend provider.

### API Surfaces

| Surface | Dialect | Endpoint | Direction |
|---------|---------|----------|-----------|
| Anthropic Messages | `src/dialects/anthropic/` | `POST /v1/messages` | Inbound & Outbound |
| Chat Completions (OpenAI-compatible) | `src/dialects/openai/` | `POST /v1/chat/completions` | Inbound & Outbound |
| Responses API (OpenAI Harmony) | `src/dialects/harmony/` | `POST /v1/responses` | Inbound & Outbound |
| Gemini | `src/dialects/gemini/` | `POST /v1beta/models/{model}:generateContent` | Inbound & Outbound |
| Codex | `src/dialects/codex/` | App server protocol | Inbound |
| Claude MCP | `src/dialects/claude_mcp/` | MCP tool serving | Inbound |

### Core Packages

| Package | Purpose |
|---------|---------|
| `src/types/` | Shared type definitions across dialects |
| `src/interop/` | Cross-dialect conversion logic |
| `src/gateway/` | Request routing and dispatch |
| `src/client/` | HTTP client for outbound requests |
| `src/sse/` | Server-Sent Events streaming |
| `src/jsonrpc/` | JSON-RPC protocol support |
| `src/mcp/` | Model Context Protocol primitives |
| `src/spawn/` | Process spawning utilities |
| `src/utils/` | Shared utilities |
| `src/wasm-gc/` | Wasm-GC target support |

### Command Targets

| Target | Path | Purpose |
|--------|------|---------|
| App Server | `cmd/app-server/` | Codex app server |
| Claude MCP Server | `cmd/claude-mcp-server/` | Claude Code MCP server |
| Native Gateway | `cmd/gateway-native/` | HTTP gateway (separate module) |
| JS Test Demo | `cmd/js-test-demo/` | JS target demo/test |


## References

### Design Documents

- [OpenAI Harmony Response Format](docs/openai-harmony.md) -- Responses API dialect design
- [Codex App Server Protocol](docs/codex-appserver.md) -- Codex CLI integration protocol
- [Claude Code MCP Server](docs/claudecode-mcp-server.md) -- MCP server for Claude Code
- [Claude MCP Serve Tools](docs/claude-mcp-serve-tools.md) -- MCP tool serving specification

### Examples

- [Codex CLI Example](examples/codex/) -- Using llm_interop with the Codex CLI
- [Claude Agent SDK Example](examples/claude-agent-sdk/) -- Using llm_interop with the Claude Agent SDK


## Development

### Build and Test

```bash
make check          # Type-check for native and js targets
make test           # Run unit tests for native and js targets
make info           # Generate .mbti interface files
make verify         # Run check + test + info (full local verification)
```

### Individual Target Commands

```bash
make check-native   # Type-check native only
make check-js       # Type-check js only
make test-native    # Test native only
make test-js        # Test js only
```

### Integration Tests

```bash
make test-integration PROVIDER=anthropic   # Requires ANTHROPIC_API_KEY
make test-integration PROVIDER=openai      # Requires OPENAI_API_KEY
make test-integration PROVIDER=groq        # Requires GROQ_API_KEY
```

### Native Gateway

The native gateway CLI is a **separate MoonBit module** at `cmd/gateway-native/`. It is excluded from the default `moon check` / `moon test` targets.

```bash
make gateway        # Run the native gateway with gateway-config.json
```

### JS Target Demo

```bash
make demo-js        # moon run --target js cmd/js-test-demo
make test-js-demo   # moon test --target js cmd/js-test-demo
```


## License

Apache-2.0 - see [LICENSE](LICENSE) for details.
