import type { Content, Part } from "@google/generative-ai";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import type { Dialect, RequestOptions } from "./types";

type ContentPart = { type: string; text?: string; url?: string };

type GeminiRequest = {
  contents: Content[];
  generationConfig?: {
    maxOutputTokens?: number;
    temperature?: number;
  };
};

function toGeminiPart(part: ContentPart): Part | null {
  switch (part.type) {
    case "text": {
      return { text: part.text ?? "" };
    }
    case "image": {
      const url = part.url ?? "";
      if (url.startsWith("data:")) {
        const commaIndex = url.indexOf(",");
        if (commaIndex === -1) {
          return null;
        }
        const header = url.slice(0, commaIndex);
        const data = url.slice(commaIndex + 1);
        const mimeTypeMatch = /data:([^;]+)/.exec(header);
        const mimeType = mimeTypeMatch?.[1] ?? "image/png";
        return { inlineData: { mimeType, data } };
      }
      return { text: `[Image: ${url}]` };
    }
    default: {
      return null;
    }
  }
}

function toGeminiContent(msg: ChatMessage): Content | null {
  if (msg.role === "system") {
    return null;
  }
  const role = msg.role === "assistant" ? "model" : "user";
  if (typeof msg.content === "string") {
    return { role, parts: [{ text: msg.content }] };
  }
  const parts = (msg.content as ContentPart[])
    .map(toGeminiPart)
    .filter((p): p is Part => p !== null);
  if (parts.length === 0) {
    return null;
  }
  return { role, parts };
}

export function buildGeminiEndpoint(model: string): string {
  return `/v1/models/${model}:generateContent`;
}

export const geminiDialect: Dialect = {
  name: "gemini",
  endpoint: "", // Dynamic, use buildGeminiEndpoint

  buildRequest(
    messages: ChatMessage[],
    _model: string,
    options?: RequestOptions
  ): GeminiRequest {
    const contents = messages
      .map(toGeminiContent)
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
