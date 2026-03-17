import type {
  MessageParam,
  ContentBlockParam,
} from "@anthropic-ai/sdk/resources/messages";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type {
  ContentPart,
  Dialect,
  ModelResponse,
  RequestOptions,
  ResponseContentBlock,
} from "./types";
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

function extractSystemText(msg: ChatMessage): string {
  if (typeof msg.content === "string") {
    return msg.content;
  }
  return "";
}

function extractSystemMessage(messages: ChatMessage[]): string {
  return messages
    .filter((m) => m.role === "system")
    .map(extractSystemText)
    .join("\n");
}

// -- Response parsing types (matching Anthropic Messages API JSON shape) --

type RawContentBlock = {
  type?: string;
  text?: string;
  thinking?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  // tool_result fields
  tool_use_id?: string;
  content?: RawContentBlock[] | string;
  is_error?: boolean;
};

type RawAnthropicResponse = {
  id?: string;
  content?: RawContentBlock[];
};

function parseToolResultContent(content: RawContentBlock[] | string | undefined): ResponseContentBlock[] {
  if (typeof content === "string") {
    return [{ type: "text", text: content }];
  }
  if (!Array.isArray(content)) {
    return [];
  }
  return content
    .map(parseContentBlock)
    .filter((b): b is ResponseContentBlock => b !== null);
}

function parseContentBlock(block: RawContentBlock): ResponseContentBlock | null {
  switch (block.type) {
    case "text": {
      if (!block.text) {
        return null;
      }
      return { type: "text", text: block.text };
    }
    case "thinking": {
      if (!block.thinking) {
        return null;
      }
      return { type: "reasoning", text: block.thinking };
    }
    case "tool_use":
    case "server_tool_use": {
      return {
        type: "tool_call",
        id: block.id ?? "",
        name: block.name ?? "",
        arguments: JSON.stringify(block.input ?? {}),
      };
    }
    case "tool_result":
    case "web_search_tool_result":
    case "code_execution_tool_result": {
      const innerContent = parseToolResultContent(block.content);
      return {
        type: "tool_result",
        toolCallId: block.tool_use_id ?? block.id ?? "",
        content: innerContent,
        ...(block.is_error ? { isError: true } : {}),
      };
    }
    default: {
      return null;
    }
  }
}

export const anthropicMessagesApiDialect: Dialect = {
  name: "anthropic-messages-api",
  supportedParams: { maxTokens: true, temperature: true, topP: true, topK: true, stop: true, reasoningEffort: false },

  buildEndpoint(): string {
    return "/v1/messages";
  },

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): unknown {
    const system = extractSystemMessage(messages);
    const converted = messages
      .map(toMessage)
      .filter((m): m is MessageParam => m !== null);

    // max_tokens is omitted when unspecified; the gateway fills it
    // from model config before forwarding to the Anthropic API.
    return {
      model,
      ...(options?.maxTokens !== undefined ? { max_tokens: options.maxTokens } : {}),
      ...(options?.temperature !== undefined ? { temperature: options.temperature } : {}),
      ...(options?.topP !== undefined ? { top_p: options.topP } : {}),
      ...(options?.topK !== undefined ? { top_k: options.topK } : {}),
      ...(options?.stop?.length ? { stop_sequences: options.stop } : {}),
      messages: converted,
      ...(system ? { system } : {}),
    };
  },

  // Anthropic Messages API returns a single response (no choices concept).
  parseResponse(response: unknown): ModelResponse {
    const resp = response as RawAnthropicResponse;
    const id = resp.id ?? "";

    const blocks = (resp.content ?? [])
      .map(parseContentBlock)
      .filter((b): b is ResponseContentBlock => b !== null);

    return { id, choices: [{ content: blocks }] };
  },
};
