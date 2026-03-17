import type {
  ChatCompletionCreateParamsNonStreaming,
  ChatCompletionMessageParam,
  ChatCompletionContentPart,
} from "openai/resources/chat/completions";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ContentPart, Dialect, RequestOptions } from "./types";

function toContentPart(part: ContentPart): ChatCompletionContentPart | null {
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

function toMessage(msg: ChatMessage): ChatCompletionMessageParam {
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
              .map(toContentPart)
              .filter((p): p is ChatCompletionContentPart => p !== null);
      return { role: "user", content };
    }
  }
}

export const openaiChatCompletionDialect: Dialect = {
  name: "openai-chat-completion",
  endpoint: "/v1/chat/completions",

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): ChatCompletionCreateParamsNonStreaming {
    return {
      model,
      messages: messages.map(toMessage),
      max_tokens: options?.maxTokens,
      temperature: options?.temperature,
      stream: false,
    };
  },
};
