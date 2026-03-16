import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import {
  getDialect,
  buildGeminiEndpoint,
  type ChatCompletionResponse,
  type RequestOptions,
} from "./dialects";

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type ApiErrorBody = {
  error?: { message?: string };
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as ApiErrorBody;
    const message = body.error?.message ?? `Request failed: ${res.status}`;
    throw new ApiError(message, res.status);
  }
  return res.json() as Promise<T>;
}

export type HealthResponse = {
  status: string;
  dialect: string;
};

export type Model = {
  id: string;
  object: string;
  owned_by: string;
};

export type ModelsResponse = {
  object: string;
  data: Model[];
};

export function fetchHealth(): Promise<HealthResponse> {
  return request<HealthResponse>("/health");
}

export function fetchModels(): Promise<ModelsResponse> {
  return request<ModelsResponse>("/v1/models");
}

export async function sendChat(
  dialect: string,
  messages: ChatMessage[],
  model: string,
  options?: RequestOptions
): Promise<ChatCompletionResponse> {
  const dialectImpl = getDialect(dialect);
  const body = dialectImpl.buildRequest(messages, model, options);

  const endpoint =
    dialect === "gemini" ? buildGeminiEndpoint(model) : dialectImpl.endpoint;

  const response = await request<unknown>(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  return parseResponse(dialect, response);
}

function parseResponse(dialect: string, response: unknown): ChatCompletionResponse {
  const resp = response as Record<string, unknown>;

  switch (dialect) {
    case "openai": {
      const choices = resp.choices as { message?: { content?: string } }[] | undefined;
      const id = typeof resp.id === "string" ? resp.id : "";
      return {
        id,
        content: choices?.[0]?.message?.content ?? "",
      };
    }
    case "anthropic": {
      const content = resp.content as { type?: string; text?: string }[] | undefined;
      const text = content?.find((c) => c.type === "text")?.text ?? "";
      const id = typeof resp.id === "string" ? resp.id : "";
      return {
        id,
        content: text,
      };
    }
    case "gemini": {
      const candidates = resp.candidates as {
        content?: { parts?: { text?: string }[] };
      }[] | undefined;
      const text = candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      return {
        id: "",
        content: text,
      };
    }
    default: {
      return { id: "", content: "" };
    }
  }
}
