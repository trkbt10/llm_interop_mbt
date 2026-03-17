import { openaiChatCompletionDialect } from "./openai-chat-completion";
import { openaiResponsesApiDialect } from "./openai-responses-api";
import { anthropicMessagesApiDialect } from "./anthropic-messages-api";
import { geminiGenerateContentDialect, buildGeminiEndpoint } from "./gemini-generate-content";
import type { Dialect, DialectName, RequestOptions, ChatCompletionResponse } from "./types";

export type { Dialect, DialectName, RequestOptions, ChatCompletionResponse };
export { buildGeminiEndpoint };

const dialects: Record<DialectName, Dialect> = {
  "openai-chat-completion": openaiChatCompletionDialect,
  "openai-responses-api": openaiResponsesApiDialect,
  "anthropic-messages-api": anthropicMessagesApiDialect,
  "gemini-generate-content": geminiGenerateContentDialect,
};

export function getDialect(name: string): Dialect {
  if (!(name in dialects)) {
    console.warn(`Unknown dialect "${name}", falling back to openai-chat-completion`);
    return openaiChatCompletionDialect;
  }
  return dialects[name as DialectName];
}

export function isValidDialect(name: string): name is DialectName {
  return name in dialects;
}
