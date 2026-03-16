import type {
  MessageCreateParamsNonStreaming,
  MessageParam,
  ContentBlockParam,
} from "@anthropic-ai/sdk/resources/messages";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { Dialect, RequestOptions } from "./types";

type ContentPart = { type: string; text?: string; url?: string };

type Base64ImageMediaType = "image/jpeg" | "image/png" | "image/gif" | "image/webp";

function toAnthropicContentBlock(part: ContentPart): ContentBlockParam | null {
  switch (part.type) {
    case "text": {
      return { type: "text", text: part.text ?? "" };
    }
    case "image": {
      const url = part.url ?? "";
      if (url.startsWith("data:")) {
        const commaIndex = url.indexOf(",");
        if (commaIndex === -1) {
          return null;
        }
        const header = url.slice(0, commaIndex);
        const base64Data = url.slice(commaIndex + 1);
        const mediaTypeMatch = /data:([^;]+)/.exec(header);
        const extractedType = mediaTypeMatch?.[1] ?? "image/png";
        const mediaType = extractedType as Base64ImageMediaType;
        const source = { type: "base64" as const, media_type: mediaType, data: base64Data };
        return { type: "image" as const, source };
      }
      return { type: "text", text: `[Image: ${url}]` };
    }
    default: {
      return null;
    }
  }
}

function toAnthropicMessage(msg: ChatMessage): MessageParam | null {
  if (msg.role === "system") {
    return null;
  }
  const role = msg.role;
  if (typeof msg.content === "string") {
    return { role, content: msg.content };
  }
  const blocks = (msg.content as ContentPart[])
    .map(toAnthropicContentBlock)
    .filter((b): b is ContentBlockParam => b !== null);
  return { role, content: blocks };
}

function extractSystemMessage(messages: ChatMessage[]): string {
  const systemMsgs = messages
    .filter((m) => m.role === "system")
    .map((m) => (typeof m.content === "string" ? m.content : ""));
  return systemMsgs.join("\n");
}

export const anthropicDialect: Dialect = {
  name: "anthropic",
  endpoint: "/v1/messages",

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): MessageCreateParamsNonStreaming {
    const system = extractSystemMessage(messages);
    const anthropicMessages = messages
      .map(toAnthropicMessage)
      .filter((m): m is MessageParam => m !== null);

    return {
      model,
      max_tokens: options?.maxTokens ?? 4096,
      messages: anthropicMessages,
      ...(system ? { system } : {}),
    };
  },
};
