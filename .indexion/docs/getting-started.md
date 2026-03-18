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
