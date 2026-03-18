/**
 * Anthropic SDK → MoonBit LLM Gateway → Ollama
 *
 * Uses the Anthropic SDK directly (bypasses Agent SDK's model validation).
 * The gateway translates Anthropic Messages API to OpenAI Chat Completions.
 */

import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({
  baseURL: process.env.ANTHROPIC_BASE_URL || "http://localhost:18080",
  apiKey: process.env.ANTHROPIC_API_KEY || "dummy",
});

console.log("Sending request via Anthropic SDK → Gateway → Ollama...");

try {
  const message = await client.messages.create({
    model: "claude-sonnet-4-6-20250514",  // aliased to backend model by gateway
    max_tokens: 256,
    messages: [{ role: "user", content: "What is 2+2? Answer in one sentence." }],
  });

  console.log("Response:");
  for (const block of message.content) {
    if (block.type === "text") {
      console.log(block.text);
    }
  }
  console.log("\nModel:", message.model);
  console.log("Usage:", JSON.stringify(message.usage));
} catch (err) {
  console.error("Error:", err.message || err);
  if (err.status) console.error("Status:", err.status);
  if (err.error) console.error("Body:", JSON.stringify(err.error));
}
