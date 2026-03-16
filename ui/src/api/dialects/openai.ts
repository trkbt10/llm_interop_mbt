import type {
  ChatCompletionCreateParamsNonStreaming,
  ChatCompletionMessageParam,
  ChatCompletionContentPart,
} from "openai/resources/chat/completions";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { Dialect, RequestOptions } from "./types";

type ContentPart = { type: string; text?: string; url?: string };

function toOpenAIContentPart(part: ContentPart): ChatCompletionContentPart | null {
  switch (part.type) {
    case "text": {
      return { type: "text", text: part.text ?? "" };
    }
    case "image": {
      return { type: "image_url", image_url: { url: part.url ?? "" } };
    }
    default: {
      return null;
    }
  }
}

function toOpenAIMessage(msg: ChatMessage): ChatCompletionMessageParam {
  switch (msg.role) {
    case "system": {
      const text = typeof msg.content === "string" ? msg.content : "";
      return { role: "system", content: text };
    }
    case "assistant": {
      const text = typeof msg.content === "string" ? msg.content : "";
      return { role: "assistant", content: text };
    }
    case "user":
    default: {
      const content =
        typeof msg.content === "string"
          ? msg.content
          : (msg.content as ContentPart[])
              .map(toOpenAIContentPart)
              .filter((p): p is ChatCompletionContentPart => p !== null);
      return { role: "user", content };
    }
  }
}

export const openaiDialect: Dialect = {
  name: "openai",
  endpoint: "/v1/chat/completions",

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): ChatCompletionCreateParamsNonStreaming {
    return {
      model,
      messages: messages.map(toOpenAIMessage),
      max_tokens: options?.maxTokens,
      temperature: options?.temperature,
      stream: false,
    };
  },
};
