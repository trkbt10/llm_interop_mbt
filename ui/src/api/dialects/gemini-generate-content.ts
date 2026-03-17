import type { Content, Part } from "@google/generative-ai";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ContentPart, Dialect, RequestOptions } from "./types";
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

export function buildGeminiEndpoint(model: string): string {
  return `/v1/models/${model}:generateContent`;
}

export const geminiGenerateContentDialect: Dialect = {
  name: "gemini-generate-content",
  endpoint: "", // Dynamic, use buildGeminiEndpoint

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
};
