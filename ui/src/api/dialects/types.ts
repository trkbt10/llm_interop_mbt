import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";

export type DialectName = "openai" | "anthropic" | "gemini";

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
