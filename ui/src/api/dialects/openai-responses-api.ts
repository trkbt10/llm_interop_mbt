import type {
  ResponseCreateParamsNonStreaming,
  ResponseInput,
  ResponseInputItem,
} from "openai/resources/responses/responses";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ContentPart, Dialect, RequestOptions } from "./types";
import { parseDataUrl } from "../../utils/dataUrl";

function toInputItem(msg: ChatMessage): ResponseInputItem {
  const role = msg.role === "assistant" ? "assistant" as const : msg.role === "system" ? "system" as const : "user" as const;

  if (typeof msg.content === "string") {
    return { role, content: msg.content };
  }

  const parts = msg.content as ContentPart[];
  const contentList = parts
    .map((part): ResponseInputItem.Message["content"][number] | null => {
      switch (part.type) {
        case "text": {
          return { type: "input_text" as const, text: part.text ?? "" };
        }
        case "image": {
          const url = part.url ?? "";
          const parsed = parseDataUrl(url);
          const imageUrl = parsed
            ? `data:${parsed.mimeType};base64,${parsed.data}`
            : url;
          return {
            type: "input_image" as const,
            detail: "auto" as const,
            image_url: imageUrl,
          };
        }
        default: {
          return null;
        }
      }
    })
    .filter(<T>(v: T | null): v is T => v !== null);

  return { role, content: contentList };
}

function toInput(messages: ChatMessage[]): { instructions: string | undefined; input: ResponseInput } {
  const systemMsgs = messages.filter((m) => m.role === "system");
  const nonSystemMsgs = messages.filter((m) => m.role !== "system");

  const instructions = systemMsgs.length > 0
    ? systemMsgs.map((m) => (typeof m.content === "string" ? m.content : "")).join("\n")
    : undefined;

  const input: ResponseInput = nonSystemMsgs.map(toInputItem);
  return { instructions, input };
}

export const openaiResponsesApiDialect: Dialect = {
  name: "openai-responses-api",
  endpoint: "/v1/responses",

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): ResponseCreateParamsNonStreaming {
    const { instructions, input } = toInput(messages);

    return {
      model,
      input,
      ...(instructions ? { instructions } : {}),
      ...(options?.maxTokens ? { max_output_tokens: options.maxTokens } : {}),
      ...(options?.temperature !== undefined ? { temperature: options.temperature } : {}),
      stream: false,
    };
  },
};
