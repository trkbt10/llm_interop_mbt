/**
 * Claude Agent SDK → MoonBit LLM Gateway → Ollama
 *
 * The SDK only accepts Claude model names internally, so we use model aliasing:
 *   SDK sends "claude-sonnet-4-6" → Gateway rewrites to backend model → Ollama
 *
 * Prerequisites:
 *   1. Start Ollama with a model (e.g. ollama run llama3)
 *   2. Start the gateway with Anthropic dialect:
 *      cd cmd/gateway-native && moon run --target native . -- \
 *        --dialect anthropic --config ../../examples/claude-agent-sdk/gateway-config.json
 *   3. Run this script:
 *      ANTHROPIC_BASE_URL=http://localhost:18080 ANTHROPIC_AUTH_TOKEN=dummy node src/agent-sdk.mjs
 */

import { query } from "@anthropic-ai/claude-agent-sdk";

process.env.ANTHROPIC_BASE_URL ??= "http://localhost:18080";
process.env.ANTHROPIC_AUTH_TOKEN ??= "dummy";

const prompt =
  process.argv[2] || "What is 2+2? Answer in one sentence.";

console.log(`Prompt: ${prompt}`);
console.log(`Model:  claude-sonnet-4-6 → backend model (via gateway model alias)`);
console.log(`Gateway: ${process.env.ANTHROPIC_BASE_URL}`);
console.log("---");

try {
  const conversation = query({
    prompt,
    options: {
      model: "sonnet",  // SDK resolves to claude-sonnet-4-6; gateway aliases to backend model
      maxTurns: 1,
      tools: [],
      permissionMode: "bypassPermissions",
      dangerouslySkipPermissions: true,
    },
  });

  for await (const message of conversation) {
    if (message.type === "assistant") {
      for (const block of message.message.content) {
        if (block.type === "text") {
          process.stdout.write(block.text);
        }
      }
      process.stdout.write("\n");
    } else if (message.type === "result") {
      console.log("\n--- Done ---");
      console.log(`Result: ${message.subtype}`);
      if (message.cost_usd != null) {
        console.log(`Cost:   $${message.cost_usd.toFixed(6)}`);
      }
      if (message.usage) {
        console.log(`Tokens: ${JSON.stringify(message.usage)}`);
      }
    }
  }
} catch (err) {
  console.error("Error:", err.message || err);
  process.exit(1);
}
