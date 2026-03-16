import { openaiDialect } from "./openai";
import { anthropicDialect } from "./anthropic";
import { geminiDialect, buildGeminiEndpoint } from "./gemini";
import type { Dialect, DialectName, RequestOptions, ChatCompletionResponse } from "./types";

export type { Dialect, DialectName, RequestOptions, ChatCompletionResponse };
export { buildGeminiEndpoint };

const dialects: Record<DialectName, Dialect> = {
  openai: openaiDialect,
  anthropic: anthropicDialect,
  gemini: geminiDialect,
};

export function getDialect(name: string): Dialect {
  if (!(name in dialects)) {
    console.warn(`Unknown dialect "${name}", falling back to OpenAI`);
    return openaiDialect;
  }
  return dialects[name as DialectName];
}

export function isValidDialect(name: string): name is DialectName {
  return name in dialects;
}
