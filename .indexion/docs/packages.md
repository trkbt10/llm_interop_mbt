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
