import type {
  MessageCreateParamsNonStreaming,
  MessageParam,
  ContentBlockParam,
} from "@anthropic-ai/sdk/resources/messages";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ContentPart, Dialect, RequestOptions } from "./types";
import { parseDataUrl } from "../../utils/dataUrl";

type Base64ImageMediaType = "image/jpeg" | "image/png" | "image/gif" | "image/webp";

function toContentBlock(part: ContentPart): ContentBlockParam | null {
  switch (part.type) {
    case "text": {
      return { type: "text", text: part.text ?? "" };
    }
    case "image": {
      const url = part.url ?? "";
      const parsed = parseDataUrl(url);
      if (parsed) {
        const mediaType = parsed.mimeType as Base64ImageMediaType;
        const source = { type: "base64" as const, media_type: mediaType, data: parsed.data };
        return { type: "image" as const, source };
      }
      return { type: "text", text: `[Image: ${url}]` };
    }
    default: {
      return null;
    }
  }
}

function toMessage(msg: ChatMessage): MessageParam | null {
  if (msg.role === "system") {
    return null;
  }
  const role = msg.role;
  if (typeof msg.content === "string") {
    return { role, content: msg.content };
  }
  const blocks = (msg.content as ContentPart[])
    .map(toContentBlock)
    .filter((b): b is ContentBlockParam => b !== null);
  return { role, content: blocks };
}

function extractSystemMessage(messages: ChatMessage[]): string {
  const systemMsgs = messages
    .filter((m) => m.role === "system")
    .map((m) => (typeof m.content === "string" ? m.content : ""));
  return systemMsgs.join("\n");
}

export const anthropicMessagesApiDialect: Dialect = {
  name: "anthropic-messages-api",
  endpoint: "/v1/messages",

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): MessageCreateParamsNonStreaming {
    const system = extractSystemMessage(messages);
    const converted = messages
      .map(toMessage)
      .filter((m): m is MessageParam => m !== null);

    return {
      model,
      max_tokens: options?.maxTokens ?? 4096,
      messages: converted,
      ...(system ? { system } : {}),
    };
  },
};
