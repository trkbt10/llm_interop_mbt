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
