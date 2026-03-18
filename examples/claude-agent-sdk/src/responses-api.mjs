/**
 * OpenAI Responses API → MoonBit LLM Gateway → Ollama
 *
 * Uses the Responses API format (/v1/responses) instead of
 * Anthropic Messages API. Requires --dialect openai.
 * Gateway translates: Responses API → Chat Completions → Ollama
 */

const GATEWAY = process.env.GATEWAY_URL || "http://localhost:18080";
const MODEL = process.argv[2] || "llama3";

async function main() {
  const body = {
    model: MODEL,
    input: [
      { role: "user", content: "What is 2+2? Answer in one sentence." },
    ],
  };

  console.log("Sending Responses API request → Gateway → Ollama...");
  console.log(`POST ${GATEWAY}/v1/responses`);
  console.log(`Model: ${body.model}`);
  console.log("---");

  const res = await fetch(`${GATEWAY}/v1/responses`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await res.json();

  if (res.status !== 200) {
    console.error(`Error ${res.status}:`, JSON.stringify(data, null, 2));
    process.exit(1);
  }

  console.log("Response (Responses API format):");
  console.log(JSON.stringify(data, null, 2));

  if (data.output) {
    for (const item of data.output) {
      if (item.type === "message" && item.content) {
        for (const block of item.content) {
          if (block.type === "output_text") {
            console.log("\nText:", block.text);
          }
        }
      }
    }
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
