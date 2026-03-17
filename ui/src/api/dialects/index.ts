import { openaiChatCompletionDialect } from "./openai-chat-completion";
import { openaiResponsesApiDialect } from "./openai-responses-api";
import { anthropicMessagesApiDialect } from "./anthropic-messages-api";
import { geminiGenerateContentDialect } from "./gemini-generate-content";
import { codexAppServerDialect } from "./codex-app-server";
import type { Dialect, DialectName, ModelResponse, RequestOptions, ResponseChoice, ResponseContentBlock, SupportedParams } from "./types";

export type { Dialect, DialectName, ModelResponse, RequestOptions, ResponseChoice, ResponseContentBlock, SupportedParams };

const dialects: Record<DialectName, Dialect> = {
  "openai-chat-completion": openaiChatCompletionDialect,
  "openai-responses-api": openaiResponsesApiDialect,
  "anthropic-messages-api": anthropicMessagesApiDialect,
  "gemini-generate-content": geminiGenerateContentDialect,
  "codex-app-server": codexAppServerDialect,
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

export const dialectNames = Object.keys(dialects) as DialectName[];

/** Map gateway surface name (from /health) to the default UI dialect */
export function surfaceToDialect(surface: string): DialectName {
  switch (surface) {
    case "anthropic":
      return "anthropic-messages-api";
    case "gemini":
      return "gemini-generate-content";
    case "codex":
      return "codex-app-server";
    case "openai":
    default:
      return "openai-chat-completion";
  }
}
