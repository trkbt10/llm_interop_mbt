/**
 * Anthropic SDK compatibility test
 * Run: npx tsx tests/sdk-compat/anthropic.ts
 * Requires: gateway running with --dialect anthropic
 */

import Anthropic from "@anthropic-ai/sdk";

const GATEWAY_URL = process.env.GATEWAY_URL ?? "http://localhost:18080";

async function testMessages() {
  console.log("Testing Anthropic Messages API...");
  console.log(`Gateway URL: ${GATEWAY_URL}`);

  const client = new Anthropic({
    baseURL: GATEWAY_URL,
    apiKey: "test-key",
  });

  // Use OpenAI model to test cross-dialect transformation
  // Gateway will route to OpenAI and transform response to Anthropic format
  const response = await client.messages.create({
    model: "gpt-4o-mini",
    max_tokens: 100,
    messages: [{ role: "user", content: "Say hello in one word." }],
  });

  console.log("Response:", JSON.stringify(response, null, 2));

  const textContent = response.content.find((block) => block.type === "text");
  if (textContent && textContent.type === "text") {
    console.log("Content:", textContent.text);
  }

  console.log("Messages API: OK\n");
}

async function testMessagesWithSystem() {
  console.log("Testing Anthropic Messages API with system prompt...");

  const client = new Anthropic({
    baseURL: GATEWAY_URL,
    apiKey: "test-key",
  });

  const response = await client.messages.create({
    model: "gpt-4o-mini",
    max_tokens: 100,
    system: "You are a helpful assistant that responds briefly.",
    messages: [{ role: "user", content: "What is 2+2?" }],
  });

  console.log("Response:", JSON.stringify(response, null, 2));
  console.log("Messages with system: OK\n");
}

async function testModels() {
  console.log("Testing Models API...");

  // Anthropic SDK doesn't have a models.list() method by default
  // We test via raw fetch
  const response = await fetch(`${GATEWAY_URL}/v1/models`);
  const data = (await response.json()) as { data: Array<{ id: string }> };

  console.log("Models count:", data.data.length);
  console.log(
    "Sample models:",
    data.data.slice(0, 3).map((m) => m.id)
  );
  console.log("Models API: OK\n");
}

async function main() {
  console.log("=== Anthropic SDK Compatibility Test ===\n");

  try {
    await testModels();
    await testMessages();
    await testMessagesWithSystem();
    console.log("All tests passed!");
  } catch (error) {
    console.error("Test failed:", error);
    process.exit(1);
  }
}

main();
