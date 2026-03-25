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

///|
test "bytes_to_string_lossy returns empty on invalid utf8" {
  let invalid = Bytes::make(2, b'\xFF')
  assert_eq(bytes_to_string_lossy(invalid), "")
}

///|
test "transport error helpers create expected variants" {
  match transport_network_error("offline") {
    TransportError::NetworkError(message) => assert_eq(message, "offline")
    _ => fail("Expected NetworkError")
  }
  match transport_timeout_error() {
    TransportError::TimeoutError => ()
    _ => fail("Expected TimeoutError")
  }
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

///|
struct NetworkErrorTransport {
  message : String
}

///|
fn NetworkErrorTransport::new(message : String) -> NetworkErrorTransport {
  { message, }
}

///|
impl HttpTransport for NetworkErrorTransport with request(self, _req) {
  raise transport_network_error(self.message)
}

///|
struct TimeoutTransport {
  dummy : Int
}

///|
fn TimeoutTransport::new() -> TimeoutTransport {
  { dummy: 0 }
}

///|
impl HttpTransport for TimeoutTransport with request(_self, _req) {
  ignore(_self.dummy)
  raise transport_timeout_error()
}

///|
struct StreamingNetworkErrorTransport {
  message : String
}

///|
fn StreamingNetworkErrorTransport::new(
  message : String,
) -> StreamingNetworkErrorTransport {
  { message, }
}

///|
impl StreamingHttpTransport for StreamingNetworkErrorTransport with request_stream(
  self,
  _req,
) {
  raise transport_network_error(self.message)
}

///|
struct MockStreamReader {
  chunks : Array[Bytes]
  mut index : Int
}

///|
fn MockStreamReader::from_strings(chunks : Array[String]) -> MockStreamReader {
  { chunks: chunks.map(fn(chunk) { @utf8.encode(chunk) }), index: 0 }
}

///|
impl StreamReader for MockStreamReader with read(self) {
  if self.index >= self.chunks.length() {
    None
  } else {
    let chunk = self.chunks[self.index]
    self.index += 1
    Some(chunk)
  }
}

///|
struct TimeoutStreamReader {
  dummy : Int
}

///|
fn TimeoutStreamReader::new() -> TimeoutStreamReader {
  { dummy: 0 }
}

///|
impl StreamReader for TimeoutStreamReader with read(self) {
  ignore(self.dummy)
  raise transport_timeout_error()
}

///|
struct MockStreamingTransport {
  mut last_url : String
  mut last_body : String
  response_status : Int
  chunks : Array[String]
}

///|
fn MockStreamingTransport::new(
  status : Int,
  chunks : Array[String],
) -> MockStreamingTransport {
  { last_url: "", last_body: "", response_status: status, chunks }
}

///|
impl StreamingHttpTransport for MockStreamingTransport with request_stream(
  self,
  req,
) {
  self.last_url = req.url
  self.last_body = req.body.unwrap_or("")
  let reader = MockStreamReader::from_strings(self.chunks)
  { status: self.response_status, reader }
}

///|
struct TimeoutReadStreamingTransport {
  mut last_url : String
  mut last_body : String
}

///|
fn TimeoutReadStreamingTransport::new() -> TimeoutReadStreamingTransport {
  { last_url: "", last_body: "" }
}

///|
impl StreamingHttpTransport for TimeoutReadStreamingTransport with request_stream(
  self,
  req,
) {
  self.last_url = req.url
  self.last_body = req.body.unwrap_or("")
  let reader = TimeoutStreamReader::new()
  { status: 200, reader }
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
  let messages = [
    @types.ModelMessage::User(content="Hi", name=None, content_parts=None),
  ]
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
    [
      @types.ModelMessage::User(
        content="weather?",
        name=None,
        content_parts=None,
      ),
    ],
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
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
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
    [
      @types.ModelMessage::User(
        content="search for test",
        name=None,
        content_parts=None,
      ),
    ],
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
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
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
    [@types.ModelMessage::User(content="read", name=None, content_parts=None)],
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
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
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
    [
      @types.ModelMessage::User(
        content="weather?",
        name=None,
        content_parts=None,
      ),
    ],
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
    [@types.ModelMessage::User(content="search", name=None, content_parts=None)],
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
    [
      @types.ModelMessage::User(
        content="weather?",
        name=None,
        content_parts=None,
      ),
    ],
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
    [
      @types.ModelMessage::User(
        content="weather?",
        name=None,
        content_parts=None,
      ),
    ],
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
    [@types.ModelMessage::User(content="search", name=None, content_parts=None)],
    [],
    "claude",
  )
  match result {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls[0].name, "search")
      assert_eq(rich.content, "Checking...")
    }
    _ => fail("expected ToolCallsWithContent from mixed Anthropic response")
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
    [@types.ModelMessage::User(content="search", name=None, content_parts=None)],
    [],
    "gemini-pro",
  )
  match result {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls[0].name, "search")
      assert_eq(rich.content, "Looking...")
    }
    _ => fail("expected ToolCallsWithContent from mixed Gemini response")
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
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
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

///|
async test "chat_gateway: sync transport network error becomes HttpError" {
  let transport = NetworkErrorTransport::new("connection reset")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAICompletions,
  )
  let mut caught = false
  let _result = chat_gateway(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4",
  ) catch {
    ClientError::HttpError(message) => {
      assert_true(message.contains("Transport error: connection reset"))
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
async test "chat_gateway: responses transport timeout becomes HttpError" {
  let transport = TimeoutTransport::new()
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let mut caught = false
  let _result = chat_gateway(
    { ..provider, base_url: "https://api.anthropic.com", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "claude-sonnet-4-20250514",
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
async test "chat_gateway_responses_stream: transport network error becomes HttpError" {
  let transport = StreamingNetworkErrorTransport::new("stream offline")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    on_event=fn(_event) {  },
  ) catch {
    ClientError::HttpError(message) => {
      assert_true(message.contains("Transport error: stream offline"))
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
async test "read_all_from_stream concatenates chunks until eof" {
  let reader = MockStreamReader::from_strings(["Hello", " ", "stream"])
  let text = read_all_from_stream(reader)
  assert_eq(text, "Hello stream")
}

///|
async test "chat_gateway_responses injects optional params and parses text" {
  let resp_body =
    #|{"id":"resp_direct","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Direct text"}]}],"status":"completed"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let result = chat_gateway_responses(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk-test" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    max_tokens=Some(64),
    temperature=Some(0.2),
  )
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "Direct text")
    _ => fail("expected Text")
  }
  assert_true(transport.last_body.contains("max_output_tokens"))
  assert_true(transport.last_body.contains("\"temperature\":0.2"))
}

///|
async test "chat_gateway_responses: 429 returns RateLimited directly" {
  let transport = MockTransport::new(429, "rate limited")
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway_responses(
    { ..provider, base_url: "https://api.anthropic.com", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "rate_limit_error")
      assert_eq(failure.retry_after, Some(60))
    }
    _ => fail("expected structured rate limit failure")
  }
}

///|
async test "chat_gateway_responses_stream reads non-2xx error body" {
  let transport = MockStreamingTransport::new(500, [
    "{\"error\":\"stream failed\"}",
  ])
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    on_event=fn(_event) {  },
  ) catch {
    ClientError::ApiError(code~, message~) => {
      assert_eq(code, 500)
      assert_true(message.contains("stream failed"))
      caught = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(caught)
  assert_true(transport.last_url.contains("/responses"))
  assert_true(transport.last_body.contains("\"model\":\"gpt-4.1\""))
}

///|
async test "chat_gateway_responses_stream accumulates native responses text" {
  let raw_events = [
    "event: response.output_text.delta\n", "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello",
    " World\",\"sequence_number\":1}\n\n", "event: response.completed\ndata: {\"type\":\"response.completed\",\"sequence_number\":2}\n\n",
  ]
  let transport = MockStreamingTransport::new(200, raw_events)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let seen : Array[String] = []
  let result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    on_event=fn(event) { seen.push(event.0) },
  )
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello World")
    _ => fail("expected Text")
  }
  assert_eq(seen, ["response.output_text.delta", "response.completed"])
  assert_true(transport.last_url.contains("/responses"))
  assert_true(transport.last_body.contains("\"model\":\"gpt-4.1\""))
}

///|
async test "chat_gateway_responses_stream: Anthropic structured JSON stream preserves text and request format" {
  let raw_events = [
    "event: content_block_delta\n", "data: {\"delta\":{\"type\":\"text_delta\",\"text\":\"{\\\"answer\\\":\"}}\n\n",
    "event: content_block_delta\n", "data: {\"delta\":{\"type\":\"text_delta\",\"text\":\"{\\\"url\\\":\\\"https://example.com\\\"}}\"}}\n\n",
    "event: message_delta\n", "data: {\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n",
    "event: message_stop\n", "data: {\"type\":\"message_stop\"}\n\n",
  ]
  let transport = MockStreamingTransport::new(200, raw_events)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let seen : Array[String] = []
  let result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.anthropic.com/v1", api_key: "sk" },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "claude-sonnet-4-20250514",
    on_event=fn(event) { seen.push(event.0) },
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
    _ => fail("expected Text")
  }
  assert_true(seen.contains("response.output_text.delta"))
  assert_true(seen.contains("response.output_text.done"))
  assert_true(seen.contains("response.completed"))
  assert_true(transport.last_body.contains("\"stream\":true"))
  assert_true(
    transport.last_body.contains(
      "\"output_config\":{\"format\":{\"type\":\"json_schema\"",
    ),
  )
  assert_true(transport.last_body.contains("\"format\":\"uri\""))
  assert_true(transport.last_body.contains("\"additionalProperties\":false"))
}

///|
async test "chat_gateway_responses_stream: OpenAI structured JSON invalid stream raises ParseError" {
  let raw_events = [
    "event: response.output_text.delta\n", "data: {\"type\":\"response.output_text.delta\",\"delta\":\"{\\\"answer\\\":oops}\"}\n\n",
  ]
  let transport = MockStreamingTransport::new(200, raw_events)
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "gpt-4.1",
    on_event=fn(_event) {  },
    response_format=Some(@types.ResponseFormat::JsonObject),
  ) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("not valid JSON"))
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
async test "chat_gateway_responses_stream: Gemini structured JSON stream preserves text and request format" {
  let raw_events = [
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"{\\\"answer\\\":\"}]}}]}\n\n",
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"{\\\"url\\\":\\\"https://example.com\\\"}}\"}]}}]}\n\n",
    "data: {\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"role\":\"model\",\"parts\":[]}}]}\n\n",
  ]
  let transport = MockStreamingTransport::new(200, raw_events)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let seen : Array[String] = []
  let result = chat_gateway_responses_stream(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      api_key: "k",
    },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "gemini-2.0-flash",
    on_event=fn(event) { seen.push(event.0) },
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
    _ => fail("expected Text")
  }
  assert_true(seen.contains("response.output_text.delta"))
  assert_true(seen.contains("response.output_text.done"))
  assert_true(seen.contains("response.completed"))
  assert_true(
    transport.last_body.contains("\"responseMimeType\":\"application/json\""),
  )
  assert_true(transport.last_body.contains("\"responseJsonSchema\""))
  assert_true(transport.last_body.contains("\"format\":\"uri\""))
  assert_false(transport.last_body.contains("\"additionalProperties\":false"))
}

///|
async test "chat_gateway_responses_stream: Anthropic structured JSON schema mismatch raises ParseError" {
  let raw_events = [
    "event: content_block_delta\n", "data: {\"delta\":{\"type\":\"text_delta\",\"text\":\"{\\\"url\\\":\\\"not-a-uri\\\"}\"}}\n\n",
    "event: message_delta\n", "data: {\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n",
    "event: message_stop\n", "data: {\"type\":\"message_stop\"}\n\n",
  ]
  let transport = MockStreamingTransport::new(200, raw_events)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let mut caught = false
  let _result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.anthropic.com/v1", api_key: "sk" },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "claude-sonnet-4-20250514",
    on_event=fn(_event) {  },
    response_format=Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "required": ["url"],
          "properties": { "url": { "type": "string", "format": "uri" } },
          "additionalProperties": false,
        },
        description=Some("Structured answer"),
        strict=Some(true),
      ),
    ),
  ) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("response schema"))
      assert_true(message.contains("$.url"))
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
async test "chat_gateway_responses: Anthropic structured JSON sync preserves raw schema semantics" {
  let resp_body =
    #|{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"{\"answer\":{\"url\":\"https://example.com\"}}"}],"stop_reason":"end_turn"}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "anthropic",
    @gateway.AnthropicMessages,
  )
  let result = chat_gateway_responses(
    { ..provider, base_url: "https://api.anthropic.com/v1", api_key: "sk" },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
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
    _ => fail("expected Text")
  }
  assert_true(
    transport.last_body.contains("\"format\":{\"type\":\"json_schema\""),
  )
  assert_true(transport.last_body.contains("\"format\":\"uri\""))
  assert_true(transport.last_body.contains("\"additionalProperties\":false"))
}

///|
async test "chat_gateway_responses: Gemini structured JSON sync preserves raw schema semantics" {
  let resp_body =
    #|{"candidates":[{"content":{"role":"model","parts":[{"text":"{\"answer\":{\"url\":\"https://example.com\"}}"}]},"finishReason":"STOP"}]}
  let transport = MockTransport::new(200, resp_body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway_responses(
    {
      ..provider,
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      api_key: "k",
    },
    transport,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "gemini-2.0-flash",
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
    _ => fail("expected Text")
  }
  assert_true(
    transport.last_body.contains("\"responseMimeType\":\"application/json\""),
  )
  assert_true(transport.last_body.contains("\"responseJsonSchema\""))
  assert_true(transport.last_body.contains("\"format\":\"uri\""))
  assert_false(transport.last_body.contains("\"additionalProperties\":false"))
}

///|
async test "chat_gateway_responses_stream converts stream read timeout to HttpError" {
  let transport = TimeoutReadStreamingTransport::new()
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    on_event=fn(_event) {  },
  ) catch {
    ClientError::HttpError(message) => {
      assert_eq(message, "Stream read timeout")
      caught = true
      @types.ModelResponse::ModelError("caught")
    }
    other => {
      ignore(other)
      @types.ModelResponse::ModelError("wrong error")
    }
  }
  assert_true(caught)
  assert_true(transport.last_url.contains("/responses"))
  assert_true(transport.last_body.contains("\"model\":\"gpt-4.1\""))
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
    [@types.ModelMessage::User(content="multi", name=None, content_parts=None)],
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
    [@types.ModelMessage::User(content="multi", name=None, content_parts=None)],
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
    [@types.ModelMessage::User(content="multi", name=None, content_parts=None)],
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
    [
      @types.ModelMessage::User(
        content="weather",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    "claude-sonnet-4-20250514",
  )
  match result {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "get_weather")
      assert_true(tool_calls[0].id.length() > 0) // tool call ID present
      assert_true(tool_calls[0].arguments.stringify().contains("Tokyo"))
      assert_true(rich.content.contains("weather in Tokyo"))
    }
    _ => fail("expected ToolCallsWithContent from Anthropic mixed fixture")
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
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4",
  )
  match result {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "rate_limit_error")
      assert_eq(failure.retry_after, Some(60))
    }
    _ => fail("expected structured rate limit failure")
  }
}
