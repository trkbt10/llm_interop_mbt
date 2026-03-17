import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";

export type ContentPart = { type: string; text?: string; url?: string };

export type DialectName = "openai-chat-completion" | "openai-responses-api" | "anthropic-messages-api" | "gemini-generate-content";

export type Dialect = {
  readonly name: DialectName;
  readonly endpoint: string;
  buildRequest: (
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ) => unknown;
};

export type RequestOptions = {
  maxTokens?: number;
  temperature?: number;
  stream?: boolean;
};

export type ChatCompletionResponse = {
  id: string;
  content: string;
};
