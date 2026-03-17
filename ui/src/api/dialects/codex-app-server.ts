import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type {
  Dialect,
  ModelResponse,
  RequestOptions,
  ResponseChoice,
  ResponseContentBlock,
} from "./types";

// Codex responses come back in OpenAI Chat Completion format
// (the MoonBit gateway transforms Codex events → OpenAI JSON)

type RawChoice = {
  message?: {
    content?: string | null;
    refusal?: string | null;
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
  return { content: blocks };
}

export const codexAppServerDialect: Dialect = {
  name: "codex-app-server",
  supportedParams: {
    maxTokens: false,
    temperature: false,
    topP: false,
    topK: false,
    stop: false,
  },

  buildEndpoint(): string {
    return "/v1/chat/completions";
  },

  buildRequest(
    messages: ChatMessage[],
    model: string,
    _options?: RequestOptions,
  ): unknown {
    // Build OpenAI-compatible request; the gateway transforms to Codex JSON-RPC
    return {
      model,
      messages: messages.map((msg) => ({
        role: msg.role,
        content:
          typeof msg.content === "string"
            ? msg.content
            : JSON.stringify(msg.content),
      })),
    };
  },

  parseResponse(response: unknown): ModelResponse {
    const resp = response as RawChatCompletionResponse;
    const id = resp.id ?? "";
    const choices = (resp.choices ?? []).map(parseChoice);
    return { id, choices };
  },
};
