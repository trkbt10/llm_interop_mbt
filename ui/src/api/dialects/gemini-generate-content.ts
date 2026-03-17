import type { Content, Part } from "@google/generative-ai";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type {
  ContentPart,
  Dialect,
  ModelResponse,
  RequestOptions,
  ResponseChoice,
  ResponseContentBlock,
} from "./types";
import { parseDataUrl } from "../../utils/dataUrl";

type GeminiRequest = {
  contents: Content[];
  generationConfig?: {
    maxOutputTokens?: number;
    temperature?: number;
  };
};

function toPart(part: ContentPart): Part | null {
  switch (part.type) {
    case "text": {
      return { text: part.text ?? "" };
    }
    case "image": {
      const url = part.url ?? "";
      const parsed = parseDataUrl(url);
      if (parsed) {
        return { inlineData: { mimeType: parsed.mimeType, data: parsed.data } };
      }
      return { text: `[Image: ${url}]` };
    }
    default: {
      return null;
    }
  }
}

function toContent(msg: ChatMessage): Content | null {
  if (msg.role === "system") {
    return null;
  }
  const role = msg.role === "assistant" ? "model" : "user";
  if (typeof msg.content === "string") {
    return { role, parts: [{ text: msg.content }] };
  }
  const parts = (msg.content as ContentPart[])
    .map(toPart)
    .filter((p): p is Part => p !== null);
  if (parts.length === 0) {
    return null;
  }
  return { role, parts };
}

// -- Response parsing types (matching Gemini generateContent JSON shape) --

type RawGeminiPart = {
  text?: string;
  functionCall?: {
    name?: string;
    args?: Record<string, unknown>;
  };
  functionResponse?: {
    name?: string;
    response?: Record<string, unknown>;
  };
  inlineData?: {
    mimeType?: string;
    data?: string;
  };
  fileData?: {
    mimeType?: string;
    fileUri?: string;
  };
  executableCode?: {
    language?: string;
    code?: string;
  };
  codeExecutionResult?: {
    outcome?: string;
    output?: string;
  };
};

type RawCandidate = {
  content?: {
    parts?: RawGeminiPart[];
  };
};

type RawGeminiResponse = {
  candidates?: RawCandidate[];
};

function parseGeminiPart(part: RawGeminiPart, callIndex: number): ResponseContentBlock | null {
  if (part.text !== undefined) {
    return { type: "text", text: part.text };
  }
  if (part.functionCall) {
    const name = part.functionCall.name ?? "";
    return {
      type: "tool_call",
      id: `gemini_${name}_${callIndex}`,
      name,
      arguments: JSON.stringify(part.functionCall.args ?? {}),
    };
  }
  if (part.functionResponse) {
    const name = part.functionResponse.name ?? "";
    return {
      type: "tool_result",
      toolCallId: `gemini_${name}_${callIndex}`,
      content: [{ type: "text", text: JSON.stringify(part.functionResponse.response ?? {}) }],
    };
  }
  if (part.inlineData?.data) {
    return {
      type: "image",
      data: part.inlineData.data,
      mimeType: part.inlineData.mimeType,
    };
  }
  if (part.fileData?.fileUri) {
    return {
      type: "file",
      fileUri: part.fileData.fileUri,
      mimeType: part.fileData.mimeType,
    };
  }
  if (part.executableCode) {
    return {
      type: "code_execution",
      language: part.executableCode.language ?? "python",
      code: part.executableCode.code ?? "",
    };
  }
  if (part.codeExecutionResult) {
    return {
      type: "code_execution_result",
      output: part.codeExecutionResult.output ?? "",
      outcome: part.codeExecutionResult.outcome,
    };
  }
  return null;
}

function parseCandidate(candidate: RawCandidate): ResponseChoice {
  const parts = candidate.content?.parts ?? [];
  let callIndex = 0;

  const blocks = parts
    .map((part) => {
      if (part.functionCall) {
        return parseGeminiPart(part, callIndex++);
      }
      return parseGeminiPart(part, callIndex);
    })
    .filter((b): b is ResponseContentBlock => b !== null);

  return { content: blocks };
}

export const geminiGenerateContentDialect: Dialect = {
  name: "gemini-generate-content",

  buildEndpoint(model: string): string {
    return `/v1/models/${model}:generateContent`;
  },

  buildRequest(
    messages: ChatMessage[],
    _model: string,
    options?: RequestOptions
  ): GeminiRequest {
    const contents = messages
      .map(toContent)
      .filter((c): c is Content => c !== null);

    const request: GeminiRequest = { contents };

    if (options?.maxTokens !== undefined || options?.temperature !== undefined) {
      request.generationConfig = {};
      if (options.maxTokens !== undefined) {
        request.generationConfig.maxOutputTokens = options.maxTokens;
      }
      if (options.temperature !== undefined) {
        request.generationConfig.temperature = options.temperature;
      }
    }

    return request;
  },

  parseResponse(response: unknown): ModelResponse {
    const resp = response as RawGeminiResponse;
    const candidates = resp.candidates ?? [];

    if (candidates.length === 0) {
      return { id: "", choices: [] };
    }

    const choices = candidates.map(parseCandidate);
    return { id: "", choices };
  },
};
