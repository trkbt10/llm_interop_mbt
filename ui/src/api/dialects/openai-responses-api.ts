import type {
  ResponseCreateParamsNonStreaming,
  ResponseInput,
  ResponseInputItem,
} from "openai/resources/responses/responses";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type {
  Annotation,
  ContentPart,
  Dialect,
  ModelResponse,
  RequestOptions,
  ResponseContentBlock,
} from "./types";
import { buildDataUrl, parseDataUrl } from "../../utils/dataUrl";

// ---------------------------------------------------------------------------
// Request building
// ---------------------------------------------------------------------------

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
            ? buildDataUrl(parsed.mimeType, parsed.data)
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

function extractSystemText(msg: ChatMessage): string {
  if (typeof msg.content === "string") {
    return msg.content;
  }
  return "";
}

function toInput(messages: ChatMessage[]): { instructions: string | undefined; input: ResponseInput } {
  const systemMsgs = messages.filter((m) => m.role === "system");
  const nonSystemMsgs = messages.filter((m) => m.role !== "system");

  const instructions = systemMsgs.length > 0
    ? systemMsgs.map(extractSystemText).join("\n")
    : undefined;

  const input: ResponseInput = nonSystemMsgs.map(toInputItem);
  return { instructions, input };
}

// ---------------------------------------------------------------------------
// Response parsing types (matching Responses API JSON shape)
// ---------------------------------------------------------------------------

type RawAnnotation = {
  type?: string;
  url?: string;
  title?: string;
  start_index?: number;
  end_index?: number;
};

type RawOutputContent = {
  type?: string;
  text?: string;
  refusal?: string;
  annotations?: RawAnnotation[];
};

type RawOutputItem = {
  type?: string;
  // message fields
  content?: RawOutputContent[];
  // function_call fields
  id?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  // web_search_call fields
  status?: string;
  action?: { query?: string };
  // function_call_output fields
  output?: string;
  // reasoning fields
  summary?: { text?: string }[];
};

type RawResponsesApiResponse = {
  id?: string;
  output?: RawOutputItem[];
  output_text?: string;
};

function parseAnnotation(raw: RawAnnotation): Annotation | null {
  if (raw.type !== "url_citation" || !raw.url) {
    return null;
  }
  return {
    type: "url_citation",
    url: raw.url,
    title: raw.title,
    startIndex: raw.start_index ?? 0,
    endIndex: raw.end_index ?? 0,
  };
}

function parseMessageContent(content: RawOutputContent): ResponseContentBlock | null {
  switch (content.type) {
    case "output_text": {
      if (!content.text) {
        return null;
      }
      const annotations = (content.annotations ?? [])
        .map(parseAnnotation)
        .filter((a): a is Annotation => a !== null);
      return {
        type: "text",
        text: content.text,
        ...(annotations.length > 0 ? { annotations } : {}),
      };
    }
    case "refusal": {
      if (!content.refusal) {
        return null;
      }
      return { type: "refusal", refusal: content.refusal };
    }
    default: {
      return null;
    }
  }
}

function parseOutputItem(item: RawOutputItem): ResponseContentBlock[] {
  const blocks: ResponseContentBlock[] = [];

  switch (item.type) {
    case "message": {
      for (const content of item.content ?? []) {
        const block = parseMessageContent(content);
        if (block) {
          blocks.push(block);
        }
      }
      break;
    }
    case "function_call": {
      blocks.push({
        type: "tool_call",
        id: item.call_id ?? item.id ?? "",
        name: item.name ?? "",
        arguments: item.arguments ?? "",
      });
      break;
    }
    case "function_call_output": {
      blocks.push({
        type: "tool_result",
        toolCallId: item.call_id ?? item.id ?? "",
        content: [{ type: "text", text: item.output ?? "" }],
      });
      break;
    }
    case "web_search_call": {
      blocks.push({
        type: "web_search",
        id: item.id ?? "",
        query: item.action?.query ?? "",
        status: item.status ?? "",
      });
      break;
    }
    case "reasoning": {
      const texts = (item.summary ?? [])
        .map((s) => s.text ?? "")
        .filter((t) => t.length > 0);
      if (texts.length > 0) {
        blocks.push({ type: "reasoning", text: texts.join("\n") });
      }
      break;
    }
  }

  return blocks;
}

export const openaiResponsesApiDialect: Dialect = {
  name: "openai-responses-api",
  supportedParams: { maxTokens: true, temperature: true, topP: true, topK: false, stop: false, reasoningEffort: true },

  buildEndpoint(): string {
    return "/v1/responses";
  },

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
      ...(options?.topP !== undefined ? { top_p: options.topP } : {}),
      ...(options?.reasoningEffort ? { reasoning: { effort: options.reasoningEffort as "low" | "medium" | "high" } } : {}),
      stream: false,
    };
  },

  parseResponse(response: unknown): ModelResponse {
    const resp = response as RawResponsesApiResponse;
    const id = resp.id ?? "";

    const blocks: ResponseContentBlock[] = [];

    if (resp.output) {
      for (const item of resp.output) {
        blocks.push(...parseOutputItem(item));
      }
    }

    // Fall back to convenience field when no output items parsed
    if (blocks.length === 0 && typeof resp.output_text === "string") {
      blocks.push({ type: "text", text: resp.output_text });
    }

    // Responses API always returns a single response (no choices concept)
    return { id, choices: [{ content: blocks }] };
  },
};
