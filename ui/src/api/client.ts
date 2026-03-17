import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";
import {
  getDialect,
  type ModelResponse,
  type RequestOptions,
} from "./dialects";
import type { ChatSettings } from "../components/SettingsPanel";

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

function parseOptionalNumber(value: string): number | undefined {
  if (!value) return undefined;
  const n = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

export function settingsToRequestOptions(settings: ChatSettings): RequestOptions {
  const maxTokens = parseOptionalNumber(settings.maxTokens);
  const temperature = parseOptionalNumber(settings.temperature);
  const topP = parseOptionalNumber(settings.topP);
  const topK = parseOptionalNumber(settings.topK);
  const stop = settings.stop
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  return {
    ...(maxTokens !== undefined && maxTokens > 0 ? { maxTokens } : {}),
    ...(temperature !== undefined ? { temperature } : {}),
    ...(topP !== undefined ? { topP } : {}),
    ...(topK !== undefined ? { topK } : {}),
    ...(stop.length > 0 ? { stop } : {}),
    ...(settings.reasoningEffort ? { reasoningEffort: settings.reasoningEffort } : {}),
  };
}

export async function sendChat(
  dialect: string,
  messages: ChatMessage[],
  model: string,
  options?: RequestOptions
): Promise<ModelResponse> {
  const dialectImpl = getDialect(dialect);
  const body = dialectImpl.buildRequest(messages, model, options);
  const endpoint = dialectImpl.buildEndpoint(model);

  const response = await request<unknown>(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  return dialectImpl.parseResponse(response);
}
