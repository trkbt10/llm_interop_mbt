///|
/// Additional wrapper-focused coverage for chat completions entrypoint

///|
async test "chat_gateway wrapper: default OpenAI base URL path returns text" {
  let transport = MockTransport::new(
    200, "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}]}",
  )
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hi")
    _ => fail("Expected text response")
  }
  assert_true(transport.last_url.contains("https://api.openai.com"))
}

///|
test "chat_gateway helpers build requests and parse transport responses" {
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let req = build_chat_gateway_request(
    { ..provider, api_key: "sk-test" },
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
    None,
    Some(0.2),
    None,
  )
  assert_true(req.url.contains("https://api.openai.com"))
  assert_true(req.url.contains("/chat/completions"))
  assert_true(req.body.unwrap_or("").contains("\"temperature\":0.2"))

  match
    parse_chat_gateway_transport_response({ status: 429, body: "rate limited" }) {
    @types.ModelResponse::RateLimited(..) => ()
    _ => fail("Expected RateLimited helper response")
  }

  match
    parse_chat_gateway_transport_response({
      status: 200,
      body: "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}]}",
    }) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hi")
    _ => fail("Expected parsed helper text response")
  }
}

///|
test "chat_gateway helpers honor explicit base_url and raise helper errors" {
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let req = build_chat_gateway_request(
    { ..provider, api_key: "sk-test", base_url: "https://example.test/v1" },
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
    Some(32),
    None,
    Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=Some("Structured answer"),
        strict=Some(true),
      ),
    ),
  )
  assert_true(req.url.contains("https://example.test"))
  assert_true(req.body.unwrap_or("").contains("\"max_tokens\":32"))
  assert_true(req.body.unwrap_or("").contains("\"response_format\""))
  assert_true(req.body.unwrap_or("").contains("\"additionalProperties\":false"))
  assert_false(req.body.unwrap_or("").contains("\"format\":\"uri\""))

  let mut api_error = false
  let _ = parse_chat_gateway_transport_response({
    status: 500,
    body: "{\"error\":{\"message\":\"bad upstream\"}}",
  }) catch {
    ClientError::ApiError(code~, message~) => {
      assert_eq(code, 500)
      assert_true(message.contains("bad upstream"))
      api_error = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(api_error)

  let mut parse_error = false
  let _ = parse_chat_gateway_transport_response({ status: 200, body: "{" }) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("JSON parse error"))
      parse_error = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(parse_error)
}

///|
async test "chat_gateway wrapper: OpenAI 429 maps to RateLimited" {
  let transport = MockTransport::new(429, "rate limited")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::RateLimited(..) => ()
    _ => fail("Expected RateLimited")
  }
}

///|
async test "chat_gateway wrapper: OpenAI transport timeout becomes HttpError" {
  let transport = TimeoutTransport::new()
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let mut caught = false
  let _result = chat_gateway(
    { ..provider, api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
  ) catch {
    ClientError::HttpError(message) => {
      assert_eq(message, "Transport timeout")
      caught = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(caught)
}

///|
async test "chat_gateway wrapper: cross-surface provider delegates to responses pipeline" {
  let transport = MockTransport::new(
    200, "{\"id\":\"msg_1\",\"model\":\"claude\",\"content\":[{\"type\":\"text\",\"text\":\"Delegated\"}],\"stop_reason\":\"end_turn\"}",
  )
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    { ..provider, api_key: "sk-ant" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "Delegated")
    _ => fail("Expected delegated text response")
  }
  assert_true(transport.last_url.contains("https://api.anthropic.com"))
}

///|
async test "chat_gateway wrapper: OpenAI structured output stays normalized on direct path" {
  let transport = MockTransport::new(
    200, "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"{}\"},\"finish_reason\":\"stop\"}]}",
  )
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
    response_format=Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=Some("Structured answer"),
        strict=Some(true),
      ),
    ),
  )
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "{}")
    _ => fail("Expected text response")
  }
  assert_true(transport.last_body.contains("\"response_format\""))
  assert_true(transport.last_body.contains("\"additionalProperties\":false"))
  assert_false(transport.last_body.contains("\"format\":\"uri\""))
}

///|
async test "chat_gateway wrapper: Anthropic structured output preserves raw schema on delegated path" {
  let transport = MockTransport::new(
    200, "{\"id\":\"msg_1\",\"model\":\"claude\",\"content\":[{\"type\":\"text\",\"text\":\"{\\\"answer\\\":{\\\"url\\\":\\\"https://example.com\\\"}}\"}],\"stop_reason\":\"end_turn\"}",
  )
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    { ..provider, api_key: "sk-ant" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "claude-sonnet-4-20250514",
    response_format=Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=Some("Structured answer"),
        strict=Some(true),
      ),
    ),
  )
  match result {
    @types.ModelResponse::Text(text) =>
      assert_eq(text, "{\"answer\":{\"url\":\"https://example.com\"}}")
    _ => fail("Expected delegated text response")
  }
  assert_true(
    transport.last_body.contains("\"format\":{\"type\":\"json_schema\""),
  )
  assert_true(transport.last_body.contains("\"format\":\"uri\""))
  assert_true(transport.last_body.contains("\"additionalProperties\":false"))
}

///|
async test "chat_gateway wrapper: OpenAI network error becomes HttpError" {
  let transport = NetworkErrorTransport::new("offline")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let mut caught = false
  let _result = chat_gateway(
    { ..provider, api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    "gpt-4",
  ) catch {
    ClientError::HttpError(message) => {
      assert_eq(message, "Transport error: offline")
      caught = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(caught)
}
