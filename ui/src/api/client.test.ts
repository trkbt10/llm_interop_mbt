import { describe, it, expect, vi, beforeEach } from "vitest";
import { fetchModels, fetchHealth, sendChat, ApiError } from "./client";

const mockFetch = vi.fn();
globalThis.fetch = mockFetch;

beforeEach(() => {
  mockFetch.mockReset();
});

describe("fetchModels", () => {
  it("returns models on success", async () => {
    const mockResponse = {
      object: "list",
      data: [
        { id: "gpt-4o", object: "model", owned_by: "openai" },
        { id: "gpt-4o-mini", object: "model", owned_by: "openai" },
      ],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const result = await fetchModels();

    expect(mockFetch).toHaveBeenCalledWith("/v1/models", undefined);
    expect(result).toEqual(mockResponse);
    expect(result.data).toHaveLength(2);
  });

  it("throws ApiError on error response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: () => Promise.resolve({}),
    });

    await expect(fetchModels()).rejects.toThrow("Request failed: 500");
  });

  it("throws ApiError instance", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: () => Promise.resolve({}),
    });

    await expect(fetchModels()).rejects.toBeInstanceOf(ApiError);
  });
});

describe("fetchHealth", () => {
  it("returns health status on success", async () => {
    const mockResponse = { status: "ok", dialect: "openai" };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const result = await fetchHealth();

    expect(mockFetch).toHaveBeenCalledWith("/health", undefined);
    expect(result).toEqual(mockResponse);
  });
});

describe("sendChat", () => {
  it("sends openai request to correct endpoint", async () => {
    const mockResponse = {
      id: "chatcmpl-123",
      choices: [{ message: { content: "Hello!" } }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const result = await sendChat("openai", messages, "gpt-4o");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/chat/completions",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.id).toBe("chatcmpl-123");
    expect(result.content).toBe("Hello!");
  });

  it("sends anthropic request to messages endpoint", async () => {
    const mockResponse = {
      id: "msg-123",
      content: [{ type: "text", text: "Hi there!" }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hello" }];
    const result = await sendChat("anthropic", messages, "claude-sonnet-4-20250514");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/messages",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.id).toBe("msg-123");
    expect(result.content).toBe("Hi there!");
  });

  it("sends gemini request to model-specific endpoint", async () => {
    const mockResponse = {
      candidates: [{ content: { parts: [{ text: "Gemini response" }] } }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Test" }];
    const result = await sendChat("gemini", messages, "gemini-pro");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/models/gemini-pro:generateContent",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.content).toBe("Gemini response");
  });

  it("throws ApiError with message from response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 400,
      json: () => Promise.resolve({ error: { message: "Invalid model" } }),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    await expect(sendChat("openai", messages, "invalid")).rejects.toThrow("Invalid model");
  });

  it("throws ApiError with status when no message", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 503,
      json: () => Promise.reject(new Error("parse error")),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const err = await sendChat("openai", messages, "gpt-4o").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).status).toBe(503);
  });
});
