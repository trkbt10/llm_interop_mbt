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
  it("parses openai chat completion text response", async () => {
    const mockResponse = {
      id: "chatcmpl-123",
      choices: [{ message: { content: "Hello!" } }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const result = await sendChat("openai-chat-completion", messages, "gpt-4o");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/chat/completions",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.id).toBe("chatcmpl-123");
    expect(result.choices).toHaveLength(1);
    expect(result.choices[0].content).toEqual([
      { type: "text", text: "Hello!" },
    ]);
  });

  it("parses openai chat completion with tool calls", async () => {
    const mockResponse = {
      id: "chatcmpl-456",
      choices: [{
        message: {
          content: null,
          tool_calls: [
            { id: "call_abc", type: "function", function: { name: "get_weather", arguments: '{"city":"Tokyo"}' } },
          ],
        },
      }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Weather?" }];
    const result = await sendChat("openai-chat-completion", messages, "gpt-4o");

    expect(result.choices[0].content).toEqual([
      { type: "tool_call", id: "call_abc", name: "get_weather", arguments: '{"city":"Tokyo"}' },
    ]);
  });

  it("handles openai chat completion with multiple choices", async () => {
    const mockResponse = {
      id: "chatcmpl-789",
      choices: [
        { message: { content: "Response A" } },
        { message: { content: "Response B" } },
      ],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const result = await sendChat("openai-chat-completion", messages, "gpt-4o");

    expect(result.choices).toHaveLength(2);
    expect(result.choices[0].content).toEqual([{ type: "text", text: "Response A" }]);
    expect(result.choices[1].content).toEqual([{ type: "text", text: "Response B" }]);
  });

  it("parses openai responses api with output_text", async () => {
    const mockResponse = {
      id: "resp-123",
      output_text: "Hi from Responses API!",
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const result = await sendChat("openai-responses-api", messages, "gpt-4o");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/responses",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.id).toBe("resp-123");
    expect(result.choices[0].content).toEqual([
      { type: "text", text: "Hi from Responses API!" },
    ]);
  });

  it("parses openai responses api with rich output items", async () => {
    const mockResponse = {
      id: "resp-456",
      output: [
        {
          type: "message",
          content: [{
            type: "output_text",
            text: "Here are the results:",
            annotations: [{ type: "url_citation", url: "https://example.com", title: "Example", start_index: 0, end_index: 10 }],
          }],
        },
        {
          type: "web_search_call",
          id: "ws_abc",
          status: "completed",
          action: { query: "test query" },
        },
      ],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Search" }];
    const result = await sendChat("openai-responses-api", messages, "gpt-4o");

    expect(result.choices[0].content).toEqual([
      {
        type: "text",
        text: "Here are the results:",
        annotations: [{ type: "url_citation", url: "https://example.com", title: "Example", startIndex: 0, endIndex: 10 }],
      },
      { type: "web_search", id: "ws_abc", query: "test query", status: "completed" },
    ]);
  });

  it("parses anthropic messages api with text and tool_use", async () => {
    const mockResponse = {
      id: "msg-123",
      content: [
        { type: "text", text: "Let me check." },
        { type: "tool_use", id: "toolu_abc", name: "get_weather", input: { city: "Tokyo" } },
      ],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hello" }];
    const result = await sendChat("anthropic-messages-api", messages, "claude-sonnet-4-20250514");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/messages",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.id).toBe("msg-123");
    expect(result.choices[0].content).toEqual([
      { type: "text", text: "Let me check." },
      { type: "tool_call", id: "toolu_abc", name: "get_weather", arguments: '{"city":"Tokyo"}' },
    ]);
  });

  it("parses gemini generate content with multiple parts", async () => {
    const mockResponse = {
      candidates: [{
        content: {
          parts: [
            { text: "Here's the answer:" },
            { text: "More detail here." },
          ],
        },
      }],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Test" }];
    const result = await sendChat("gemini-generate-content", messages, "gemini-pro");

    expect(mockFetch).toHaveBeenCalledWith(
      "/v1/models/gemini-pro:generateContent",
      expect.objectContaining({ method: "POST" })
    );
    expect(result.choices[0].content).toEqual([
      { type: "text", text: "Here's the answer:" },
      { type: "text", text: "More detail here." },
    ]);
  });

  it("parses gemini with function calls and multiple candidates", async () => {
    const mockResponse = {
      candidates: [
        {
          content: {
            parts: [
              { functionCall: { name: "search", args: { q: "test" } } },
            ],
          },
        },
        {
          content: {
            parts: [{ text: "Alternative response" }],
          },
        },
      ],
    };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Test" }];
    const result = await sendChat("gemini-generate-content", messages, "gemini-pro");

    expect(result.choices).toHaveLength(2);
    expect(result.choices[0].content).toEqual([
      { type: "tool_call", id: "gemini_search_0", name: "search", arguments: '{"q":"test"}' },
    ]);
    expect(result.choices[1].content).toEqual([
      { type: "text", text: "Alternative response" },
    ]);
  });

  it("throws ApiError with message from response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 400,
      json: () => Promise.resolve({ error: { message: "Invalid model" } }),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    await expect(sendChat("openai-chat-completion", messages, "invalid")).rejects.toThrow("Invalid model");
  });

  it("throws ApiError with status when no message", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 503,
      json: () => Promise.reject(new Error("parse error")),
    });

    const messages = [{ id: "1", role: "user" as const, content: "Hi" }];
    const err = await sendChat("openai-chat-completion", messages, "gpt-4o").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).status).toBe(503);
  });
});
