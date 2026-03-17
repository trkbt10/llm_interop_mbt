import type {
  ChatCompletionCreateParamsNonStreaming,
  ChatCompletionMessageParam,
  ChatCompletionContentPart,
} from "openai/resources/chat/completions";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type {
  ContentPart,
  Dialect,
  ModelResponse,
  RequestOptions,
  ResponseChoice,
  ResponseContentBlock,
} from "./types";

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
  if (typeof msg.content === "string") {
    switch (msg.role) {
      case "system":
        return { role: "system", content: msg.content };
      case "assistant":
        return { role: "assistant", content: msg.content };
      default:
        return { role: "user", content: msg.content };
    }
  }

  const content = (msg.content as ContentPart[])
    .map(toContentPart)
    .filter((p): p is ChatCompletionContentPart => p !== null);

  switch (msg.role) {
    case "system":
      return { role: "system", content: "" };
    case "assistant":
      return { role: "assistant", content: "" };
    default:
      return { role: "user", content };
  }
}

// -- Response parsing types (matching OpenAI Chat Completions JSON shape) --

type RawToolCall = {
  id?: string;
  type?: string;
  function?: { name?: string; arguments?: string };
};

type RawChoice = {
  message?: {
    content?: string | null;
    refusal?: string | null;
    tool_calls?: RawToolCall[];
    audio?: { data?: string };
  };
};

type RawChatCompletionResponse = {
  id?: string;
  choices?: RawChoice[];
};

function parseChoice(choice: RawChoice): ResponseChoice {
  const blocks: ResponseContentBlock[] = [];
  const message = choice.message;
  if (!message) {
    return { content: blocks };
  }

  if (message.content) {
    blocks.push({ type: "text", text: message.content });
  }

  if (message.refusal) {
    blocks.push({ type: "refusal", refusal: message.refusal });
  }

  if (message.audio?.data) {
    blocks.push({ type: "audio", data: message.audio.data });
  }

  if (message.tool_calls) {
    for (const tc of message.tool_calls) {
      blocks.push({
        type: "tool_call",
        id: tc.id ?? "",
        name: tc.function?.name ?? "",
        arguments: tc.function?.arguments ?? "",
      });
    }
  }

  return { content: blocks };
}

export const openaiChatCompletionDialect: Dialect = {
  name: "openai-chat-completion",
  supportedParams: { maxTokens: true, temperature: true, topP: true, topK: false, stop: true },

  buildEndpoint(): string {
    return "/v1/chat/completions";
  },

  buildRequest(
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ): ChatCompletionCreateParamsNonStreaming {
    return {
      model,
      messages: messages.map(toMessage),
      ...(options?.maxTokens !== undefined ? { max_tokens: options.maxTokens } : {}),
      ...(options?.temperature !== undefined ? { temperature: options.temperature } : {}),
      ...(options?.topP !== undefined ? { top_p: options.topP } : {}),
      ...(options?.stop?.length ? { stop: options.stop } : {}),
      stream: false,
    };
  },

  parseResponse(response: unknown): ModelResponse {
    const resp = response as RawChatCompletionResponse;
    const id = resp.id ?? "";
    const choices = (resp.choices ?? []).map(parseChoice);
    return { id, choices };
  },
};
