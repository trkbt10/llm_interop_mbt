# llm_interop

**LLM Gateway -- a protocol translation layer between AI developer tools and LLM backends, written in MoonBit.**

llm_interop translates between Anthropic Messages API, OpenAI Chat Completions API, and OpenAI Responses API, letting you route requests from any client to any backend. This means tools like Claude Code, OpenAI Codex CLI, and the Claude Agent SDK can run against local models (e.g., Ollama) or any OpenAI-compatible endpoint without modification.

- **Protocol bridging across three API surfaces** -- accepts Anthropic Messages, OpenAI Chat Completions, and OpenAI Responses API requests and translates them to whichever format the backend expects
- **Run AI developer tools against any backend** -- use Claude Code, Codex CLI, or the Claude Agent SDK with Ollama, OpenAI, Gemini, or any OpenAI-compatible API by simply changing the gateway config
- **Model aliasing and parameter harmonization** -- rewrites model names (e.g., `claude-sonnet-4-6` to `llama3`) and normalizes parameters like `max_output_tokens` to `max_tokens` so clients and backends speak the same language
