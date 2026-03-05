///|
/// Client tests

///|
test "ClientConfig::new creates config with defaults" {
  let config = ClientConfig::new(Provider::OpenAI, "test-key", "gpt-4")
  assert_eq(config.api_key, "test-key")
  assert_eq(config.model, "gpt-4")
  assert_eq(config.max_tokens, 4096)
  assert_true(config.temperature is None)
}

///|
test "ClientConfig::new with custom values" {
  let config = ClientConfig::new(
    Provider::Anthropic,
    "anthropic-key",
    "claude-sonnet-4-20250514",
    max_tokens=8192,
    temperature=Some(0.7),
  )
  assert_eq(config.max_tokens, 8192)
  assert_eq(config.temperature, Some(0.7))
}

///|
test "get_endpoint returns correct URLs" {
  assert_eq(get_endpoint(Provider::Anthropic), "https://api.anthropic.com/v1/messages")
  assert_eq(get_endpoint(Provider::OpenAI), "https://api.openai.com/v1/chat/completions")
  assert_eq(
    get_endpoint(Provider::OpenAICompatible(base_url="http://localhost:8080")),
    "http://localhost:8080/v1/chat/completions",
  )
}

///|
test "get_headers for Anthropic" {
  let config = ClientConfig::new(Provider::Anthropic, "test-api-key", "claude-3")
  let headers = get_headers(config)
  assert_eq(headers.get("Content-Type"), Some("application/json"))
  assert_eq(headers.get("x-api-key"), Some("test-api-key"))
  assert_eq(headers.get("anthropic-version"), Some("2023-06-01"))
}

///|
test "get_headers for OpenAI" {
  let config = ClientConfig::new(Provider::OpenAI, "sk-test-key", "gpt-4")
  let headers = get_headers(config)
  assert_eq(headers.get("Content-Type"), Some("application/json"))
  assert_eq(headers.get("Authorization"), Some("Bearer sk-test-key"))
}

///|
test "build_request_body for Anthropic" {
  let config = ClientConfig::new(Provider::Anthropic, "key", "claude-3", max_tokens=1024)
  let messages : Array[@types.ModelMessage] = [@types.ModelMessage::User(content="Hello", name=None)]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_request_body(config, messages, tools)
  let json : Json = @json.parse(body) catch {
    _ => {
      fail("parse error")
      return
    }
  }
  match json {
    { "model": String(model), "max_tokens": Number(max_tokens, ..), "messages": Array(_), .. } => {
      assert_eq(model, "claude-3")
      assert_eq(max_tokens.to_int(), 1024)
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "build_request_body for OpenAI" {
  let config = ClientConfig::new(Provider::OpenAI, "key", "gpt-4", max_tokens=2048)
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::System("You are helpful"),
    @types.ModelMessage::User(content="Hi", name=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_request_body(config, messages, tools)
  let json : Json = @json.parse(body) catch {
    _ => {
      fail("parse error")
      return
    }
  }
  match json {
    { "model": String(model), "messages": Array(msgs), .. } => {
      assert_eq(model, "gpt-4")
      assert_eq(msgs.length(), 2)
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "parse_sse_events for OpenAI format" {
  let content =
    #|data: {"choices":[{"delta":{"content":"Hello"}}]}
    #|
    #|data: {"choices":[{"delta":{"content":" World"}}]}
    #|
    #|data: [DONE]
    #|
  let result = parse_sse_events(content, Provider::OpenAI)
  assert_eq(result.events.length(), 2)
  assert_eq(result.remaining, "")
}

///|
test "parse_sse_events for Anthropic format" {
  let content =
    #|event: content_block_delta
    #|data: {"type":"content_block_delta","delta":{"text":"Hi"}}
    #|
    #|event: message_stop
    #|data: {"type":"message_stop"}
    #|
  let result = parse_sse_events(content, Provider::Anthropic)
  assert_eq(result.events.length(), 2)
  assert_eq(result.events[0].event, "content_block_delta")
}

///|
test "parse_sse_events handles incomplete chunks" {
  let content = "data: {\"partial\":"
  let result = parse_sse_events(content, Provider::OpenAI)
  assert_eq(result.events.length(), 0)
  assert_eq(result.remaining, "data: {\"partial\":")
}

///|
test "split_lines handles various line endings" {
  let s = "line1\nline2\r\nline3"
  let lines = split_lines(s)
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "line1")
  assert_eq(lines[1], "line2")
  assert_eq(lines[2], "line3")
}

///|
test "safe_substring extracts correctly" {
  assert_eq(safe_substring("event: hello", 7), "hello")
  assert_eq(safe_substring("data: {}", 6), "{}")
  assert_eq(safe_substring("short", 10), "")
}
