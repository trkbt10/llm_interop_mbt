///|
/// Client tests

// =============================================================================
// SSE / utils tests
// =============================================================================

///|
test "parse_sse_chunk for OpenAI format" {
  let content =
    #|data: {"choices":[{"delta":{"content":"Hello"}}]}
    #|
    #|data: {"choices":[{"delta":{"content":" World"}}]}
    #|
    #|data: [DONE]
    #|
  let result = @sse.parse_sse_chunk(content)
  assert_eq(result.events.length(), 2)
  assert_eq(result.remaining, "")
}

///|
test "parse_sse_chunk for Anthropic format" {
  let content =
    #|event: content_block_delta
    #|data: {"type":"content_block_delta","delta":{"text":"Hi"}}
    #|
    #|event: message_stop
    #|data: {"type":"message_stop"}
    #|
  let result = @sse.parse_sse_chunk(content)
  assert_eq(result.events.length(), 2)
  assert_eq(result.events[0].event, "content_block_delta")
}

///|
test "parse_sse_chunk handles incomplete chunks" {
  let content = "data: {\"partial\":"
  let result = @sse.parse_sse_chunk(content)
  assert_eq(result.events.length(), 0)
  assert_eq(result.remaining, "data: {\"partial\":")
}

///|
test "split_lines handles various line endings" {
  let s = "line1\nline2\r\nline3"
  let lines = @utils.split_lines(s)
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "line1")
  assert_eq(lines[1], "line2")
  assert_eq(lines[2], "line3")
}

// =============================================================================
// Mock HttpTransport for chat_gateway() tests
// =============================================================================

///|
struct MockTransport {
  mut last_url : String
  mut last_body : String
  response_status : Int
  response_body : String
}

///|
fn MockTransport::new(status : Int, body : String) -> MockTransport {
  { last_url: "", last_body: "", response_status: status, response_body: body }
}

///|
impl HttpTransport for MockTransport with request(self, req) {
  self.last_url = req.url
  self.last_body = req.body.unwrap_or("")
  { status: self.response_status, body: self.response_body }
}

// =============================================================================
// chat_gateway() end-to-end tests
// =============================================================================

///|
async test "chat_gateway: OpenAI CC text response" {
  let resp_body =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let messages = [@types.ModelMessage::User(content="Hi", name=None)]
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk-test" },
    transport,
    messages,
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::Text(t) => assert_eq(t, "Hello!")
    _ => fail("expected Text")
  }
  // Verify URL was constructed correctly
  assert_true(transport.last_url.contains("/chat/completions"))
}

///|
async test "chat_gateway: OpenAI CC tool_calls response" {
  let resp_body =
    #|{"id":"chatcmpl-2","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},"finish_reason":"tool_calls"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="weather?", name=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: Anthropic text response via transform pipeline" {
  // Anthropic native response — transform_response will convert to OpenAI format
  let resp_body =
    #|{"id":"msg_01","model":"claude","content":[{"type":"text","text":"Bonjour"}],"stop_reason":"end_turn"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://api.anthropic.com",
      api_key: "sk-ant-test",
    },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None)],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::Text(t) => assert_eq(t, "Bonjour")
    _ => fail("expected Text")
  }
  // Verify request was transformed to Anthropic format
  assert_true(transport.last_url.contains("/messages"))
  assert_true(transport.last_body.contains("claude-sonnet-4-20250514"))
}

///|
async test "chat_gateway: Anthropic tool_use response via transform pipeline" {
  let resp_body =
    #|{"id":"msg_02","model":"claude","content":[{"type":"tool_use","id":"toolu_01","name":"search","input":{"q":"test"}}],"stop_reason":"tool_use"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://api.anthropic.com",
      api_key: "sk-ant-test",
    },
    transport,
    [@types.ModelMessage::User(content="search for test", name=None)],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "search")
    }
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: Gemini text response via transform pipeline" {
  let resp_body =
    #|{"candidates":[{"content":{"parts":[{"text":"Konnichiwa"}],"role":"model"},"finishReason":"STOP"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "key",
    },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None)],
    [],
    "gemini-pro",
  )
  match result {
    @types.ModelResponse::Text(t) => assert_eq(t, "Konnichiwa")
    _ => fail("expected Text")
  }
}

///|
async test "chat_gateway: Gemini functionCall response via transform pipeline" {
  let resp_body =
    #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read_file","args":{"path":"/tmp/x"}}}],"role":"model"},"finishReason":"STOP"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "key",
    },
    transport,
    [@types.ModelMessage::User(content="read", name=None)],
    [],
    "gemini-pro",
  )
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "read_file")
    }
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: OpenAI Responses API text response" {
  let resp_body =
    #|{"id":"resp_01","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello from Responses"}]}],"status":"completed"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::Text(t) => assert_eq(t, "Hello from Responses")
    _ => fail("expected Text")
  }
  // Verify URL uses responses endpoint
  assert_true(transport.last_url.contains("/responses"))
}

///|
async test "chat_gateway: Anthropic request includes tools after transform" {
  let resp_body =
    #|{"id":"msg_03","model":"claude","content":[{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"city":"SF"}}],"stop_reason":"tool_use"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let tool = @types.ToolDefinition::new(
    name="get_weather",
    description="Get weather for a city",
    parameters={
      "type": "object",
      "properties": { "city": { "type": "string" } },
    },
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://api.anthropic.com",
      api_key: "sk-ant-test",
    },
    transport,
    [@types.ModelMessage::User(content="weather?", name=None)],
    [tool],
    "claude-sonnet-4-20250514",
  )
  // Verify the request body sent to Anthropic contains tools in Anthropic format
  assert_true(transport.last_body.contains("get_weather"))
  assert_true(transport.last_body.contains("input_schema"))
  // Verify response was parsed correctly
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: Gemini request includes tools after transform" {
  let resp_body =
    #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"search","args":{"q":"hello"}}}],"role":"model"},"finishReason":"STOP"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let tool = @types.ToolDefinition::new(
    name="search",
    description="Search the web",
    parameters={ "type": "object", "properties": { "q": { "type": "string" } } },
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "key",
    },
    transport,
    [@types.ModelMessage::User(content="search", name=None)],
    [tool],
    "gemini-pro",
  )
  // Verify the request body sent to Gemini contains tools in Gemini format
  assert_true(transport.last_body.contains("search"))
  assert_true(transport.last_body.contains("functionDeclarations"))
  // Verify response
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "search")
    }
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: OpenAI CC with tools in request" {
  let resp_body =
    #|{"id":"cc-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},"finish_reason":"tool_calls"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let tool = @types.ToolDefinition::new(
    name="get_weather",
    description="Get weather",
    parameters={
      "type": "object",
      "properties": { "city": { "type": "string" } },
    },
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="weather?", name=None)],
    [tool],
    "gpt-4",
  )
  assert_true(transport.last_body.contains("get_weather"))
  assert_true(transport.last_body.contains("\"type\":\"function\""))
  match result {
    @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "get_weather")
    _ => fail("expected ToolCalls")
  }
}

///|
async test "chat_gateway: OpenAI Responses API tool_calls response" {
  let resp_body =
    #|{"id":"resp_01","output":[{"type":"function_call","id":"fc_01","call_id":"fc_01","name":"get_weather","arguments":"{\"city\":\"Tokyo\"}","status":"completed"}],"status":"completed"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="weather?", name=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 1)
      assert_eq(c[0].name, "get_weather")
    }
    _ => fail("expected ToolCalls from Responses API")
  }
}

///|
async test "chat_gateway: Anthropic mixed text+tool_use response" {
  let resp_body =
    #|{"id":"msg_m","model":"claude","content":[{"type":"text","text":"Checking..."},{"type":"tool_use","id":"toolu_m","name":"search","input":{"q":"test"}}],"stop_reason":"tool_use"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.anthropic.com", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="search", name=None)],
    [],
    "claude",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "search")
    _ => fail("expected ToolCalls from mixed Anthropic response")
  }
}

///|
async test "chat_gateway: Gemini mixed text+functionCall response" {
  let resp_body =
    #|{"candidates":[{"content":{"parts":[{"text":"Looking..."},{"functionCall":{"name":"search","args":{"q":"test"}}}],"role":"model"},"finishReason":"STOP"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "k",
    },
    transport,
    [@types.ModelMessage::User(content="search", name=None)],
    [],
    "gemini-pro",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "search")
    _ => fail("expected ToolCalls from mixed Gemini response")
  }
}

///|
async test "chat_gateway: 500 raises ApiError" {
  let transport = MockTransport::new(
    500, "{\"error\":{\"message\":\"internal error\"}}",
  )
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let mut caught = false
  let _result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None)],
    [],
    "gpt-4",
  ) catch {
    ClientError::ApiError(code~, message~) => {
      assert_eq(code, 500)
      assert_true(message.contains("internal error"))
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

// =============================================================================
// Multi-tool E2E via chat_gateway() with real fixtures
// =============================================================================

///|
fn load_fx(path : String) -> String {
  @utils.read_testdata(path) catch {
    _ => ""
  }
}

///|
async test "chat_gateway/multi-tool/openai: 2 tools, names args IDs" {
  let resp = load_fx(
    "testdata/openai/chat_completions/live_multi_toolcall_20250321.json",
  )
  let transport = MockTransport::new(200, resp)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="multi", name=None)],
    [],
    "gpt-4o-mini",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
      assert_true(c[0].arguments.stringify().contains("Tokyo"))
      assert_true(c[1].arguments.stringify().contains("config.json"))
      assert_true(c[0].id.has_prefix("call_"))
      assert_true(c[0].id != c[1].id)
    }
    _ => fail("expected 2 ToolCalls")
  }
}

///|
async test "chat_gateway/multi-tool/groq: 2 tools via OpenAI CC" {
  let resp = load_fx(
    "testdata/groq/chat_completions/live_multi_toolcall_20250321.json",
  )
  let transport = MockTransport::new(200, resp)
  let provider = @gateway.ProviderConfig::new(
    "groq",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.groq.com/openai", api_key: "gsk" },
    transport,
    [@types.ModelMessage::User(content="multi", name=None)],
    [],
    "llama-3.3-70b-versatile",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
      assert_true(c[0].id != c[1].id)
    }
    _ => fail("expected 2 ToolCalls from Groq")
  }
}

///|
async test "chat_gateway/multi-tool/gemini: 2 tools via transform pipeline" {
  let resp = load_fx(
    "testdata/gemini/generate_content/multi_toolcall_nonstream.json",
  )
  let transport = MockTransport::new(200, resp)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "k",
    },
    transport,
    [@types.ModelMessage::User(content="multi", name=None)],
    [],
    "gemini-2.0-flash",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "get_time")
      assert_true(c[0].arguments.stringify().contains("Tokyo"))
      assert_true(c[1].arguments.stringify().contains("Asia/Tokyo"))
      assert_true(c[0].id != c[1].id)
    }
    _ => fail("expected 2 ToolCalls from Gemini")
  }
}

///|
async test "chat_gateway/multi-tool/anthropic mixed: text + 1 tool via transform" {
  let resp = load_fx("testdata/anthropic/messages/toolcall_nonstream.json")
  let transport = MockTransport::new(200, resp)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.anthropic.com", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="weather", name=None)],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 1)
      assert_eq(c[0].name, "get_weather")
      assert_true(c[0].id.length() > 0) // tool call ID present
      assert_true(c[0].arguments.stringify().contains("Tokyo"))
    }
    _ => fail("expected ToolCalls from Anthropic mixed fixture")
  }
}

///|
async test "chat_gateway: 429 returns RateLimited" {
  let transport = MockTransport::new(429, "rate limited")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::RateLimited(..) => ()
    _ => fail("expected RateLimited")
  }
}
