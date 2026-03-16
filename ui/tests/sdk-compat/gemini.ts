/**
 * Google Generative AI SDK compatibility test
 * Run: npx tsx tests/sdk-compat/gemini.ts
 * Requires: gateway running with --dialect gemini
 *
 * Note: Google's SDK doesn't easily support custom baseURL.
 * This test uses raw fetch to verify endpoint compatibility.
 */

const GATEWAY_URL = process.env.GATEWAY_URL ?? "http://localhost:18080";

type GeminiResponse = {
  candidates?: Array<{
    content?: {
      parts?: Array<{ text?: string }>;
      role?: string;
    };
    finishReason?: string;
  }>;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  };
};

type ModelsResponse = {
  data: Array<{ id: string; owned_by: string }>;
};

async function testGenerateContent() {
  console.log("Testing Gemini generateContent API...");
  console.log(`Gateway URL: ${GATEWAY_URL}`);

  const model = "gpt-4o-mini";
  const endpoint = `${GATEWAY_URL}/v1/models/${model}:generateContent`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: "Say hello in one word." }],
        },
      ],
      generationConfig: {
        maxOutputTokens: 100,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${await response.text()}`);
  }

  const data = (await response.json()) as GeminiResponse;
  console.log("Response:", JSON.stringify(data, null, 2));

  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  console.log("Content:", text);
  console.log("generateContent: OK\n");
}

async function testGenerateContentMultiturn() {
  console.log("Testing Gemini generateContent with multi-turn...");

  const model = "gpt-4o-mini";
  const endpoint = `${GATEWAY_URL}/v1/models/${model}:generateContent`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: "My name is Alice." }],
        },
        {
          role: "model",
          parts: [{ text: "Nice to meet you, Alice!" }],
        },
        {
          role: "user",
          parts: [{ text: "What is my name?" }],
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${await response.text()}`);
  }

  const data = (await response.json()) as GeminiResponse;
  console.log("Response:", JSON.stringify(data, null, 2));
  console.log("Multi-turn: OK\n");
}

async function testModels() {
  console.log("Testing Models API...");

  const response = await fetch(`${GATEWAY_URL}/v1/models`);
  const data = (await response.json()) as ModelsResponse;

  console.log("Models count:", data.data.length);
  console.log(
    "Sample models:",
    data.data.slice(0, 3).map((m) => m.id)
  );
  console.log("Models API: OK\n");
}

async function main() {
  console.log("=== Gemini SDK Compatibility Test ===\n");

  try {
    await testModels();
    await testGenerateContent();
    await testGenerateContentMultiturn();
    console.log("All tests passed!");
  } catch (error) {
    console.error("Test failed:", error);
    process.exit(1);
  }
}

main();
