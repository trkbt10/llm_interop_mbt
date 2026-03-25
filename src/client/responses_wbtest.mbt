///|
/// Additional whitebox coverage for client helper paths

///|
struct StreamingTimeoutTransport {
  dummy : Int
}

///|
fn StreamingTimeoutTransport::new() -> StreamingTimeoutTransport {
  { dummy: 0 }
}

///|
impl StreamingHttpTransport for StreamingTimeoutTransport with request_stream(
  self,
  _req,
) {
  ignore(self.dummy)
  raise transport_timeout_error()
}

///|
test "inject_optional_params mutates object bodies and ignores scalars" {
  let object_body : Json = Json::object({})
  inject_optional_params(object_body, Some(64), Some(0.25))
  match object_body {
    {
      "max_output_tokens": Number(max_output_tokens, ..),
      "temperature": Number(temperature, ..),
      ..
    } => {
      assert_eq(max_output_tokens.to_int(), 64)
      assert_eq(temperature, 0.25)
    }
    _ => fail("Expected injected optional params")
  }

  let untouched_object : Json = Json::object({})
  inject_optional_params(untouched_object, None, None)
  match untouched_object {
    Object(obj) => assert_eq(obj.length(), 0)
    _ => fail("Expected empty object")
  }

  let scalar_body : Json = Json::string("plain")
  inject_optional_params(scalar_body, Some(1), Some(0.1))
  match scalar_body {
    String(text) => assert_eq(text, "plain")
    _ => fail("Expected scalar JSON to stay unchanged")
  }
}

///|
test "apply_response_format_to_transport_body uses target-native carriers" {
  let openai_chat_body = apply_response_format_to_transport_body(
    @gateway.OpenAICompletions,
    "{\"model\":\"gpt-4.1\"}",
    Some(@types.ResponseFormat::JsonObject),
  )
  assert_true(
    openai_chat_body.contains("\"response_format\":{\"type\":\"json_object\""),
  )

  let openai_body = apply_response_format_to_transport_body(
    @gateway.OpenAIResponses,
    "{\"model\":\"gpt-4.1\"}",
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
  assert_true(openai_body.contains("\"text\":{\"format\":"))
  assert_true(openai_body.contains("\"additionalProperties\":false"))
  assert_false(openai_body.contains("\"format\":\"uri\""))

  let anthropic_body = apply_response_format_to_transport_body(
    @gateway.AnthropicMessages,
    "{\"model\":\"claude-sonnet-4-20250514\"}",
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
  assert_true(
    anthropic_body.contains(
      "\"output_config\":{\"format\":{\"type\":\"json_schema\"",
    ),
  )
  assert_true(anthropic_body.contains("\"format\":\"uri\""))
  assert_true(anthropic_body.contains("\"additionalProperties\":false"))

  let gemini_body = apply_response_format_to_transport_body(
    @gateway.GoogleGenerativeAI,
    "{\"contents\":[]}",
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
  assert_true(gemini_body.contains("\"responseMimeType\":\"application/json\""))
  assert_true(gemini_body.contains("\"responseJsonSchema\""))
  assert_true(gemini_body.contains("\"format\":\"uri\""))
  assert_false(gemini_body.contains("\"additionalProperties\":false"))

  let passthrough = apply_response_format_to_transport_body(
    @gateway.OpenAIResponses,
    "not-json",
    Some(@types.ResponseFormat::JsonObject),
  )
  assert_eq(passthrough, "not-json")

  let scalar_passthrough = apply_response_format_to_transport_body(
    @gateway.OpenAIResponses,
    "\"plain\"",
    Some(@types.ResponseFormat::JsonObject),
  )
  assert_eq(scalar_passthrough, "\"plain\"")

  let none_passthrough = apply_response_format_to_transport_body(
    @gateway.OpenAIResponses,
    "{\"model\":\"gpt-4.1\"}",
    None,
  )
  assert_eq(none_passthrough, "{\"model\":\"gpt-4.1\"}")
}

///|
test "responses helpers build requests, parse sync responses, and process stream chunks" {
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let req = build_responses_transport_request(
    { ..provider, api_key: "sk", base_url: "https://api.openai.com/v1" },
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    Some(64),
    Some(0.1),
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
    true,
  )
  assert_true(req.url.contains("/responses"))
  let body = req.body.unwrap_or("")
  assert_true(body.contains("\"max_output_tokens\":64"))
  assert_true(body.contains("\"temperature\":0.1"))
  assert_true(body.contains("\"text\":{\"format\":"))
  assert_true(body.contains("\"stream\":true"))
  assert_true(body.contains("\"additionalProperties\":false"))
  assert_false(body.contains("\"format\":\"uri\""))

  match
    parse_responses_transport_response(@gateway.OpenAIResponses, "gpt-4.1", {
      status: 429,
      body: "rate limited",
    }) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "rate_limit_error")
      assert_eq(failure.retry_after, Some(60))
      assert_eq(failure.body, Some("rate limited"))
    }
    _ => fail("Expected structured rate limit helper response")
  }

  match
    parse_responses_transport_response(@gateway.OpenAIResponses, "gpt-4.1", {
      status: 200,
      body: "{\"id\":\"resp_1\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}],\"status\":\"completed\"}",
    }) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected parsed Responses helper text")
  }

  let translator = @gateway.create_responses_api_translator(
    @gateway.OpenAIResponses,
    response_id="resp_1",
    model="gpt-4.1",
  )
  let acc = @openai.ResponsesApiAccumulator::new()
  let emitted : Array[String] = []
  let chunk_text =
    #|event: response.output_text.delta
    #|data: {"type":"response.output_text.delta","delta":"Hello"}
    #|
  let remaining = process_responses_stream_chunk(
    translator,
    acc,
    StructuredStreamValidator::new(None),
    "",
    @utf8.encode(chunk_text),
    fn(event) { emitted.push(event.0) },
  )
  assert_eq(remaining, "")
  assert_eq(emitted, ["response.output_text.delta"])
  match acc.finish() {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected accumulated helper text")
  }
}

///|
test "responses helpers honor default base_url and preserve partial SSE chunks" {
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let req = build_responses_transport_request(
    { ..provider, api_key: "sk" },
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    None,
    None,
    None,
    false,
  )
  assert_true(req.url.contains("https://api.openai.com"))
  assert_true(req.body.unwrap_or("").contains("\"model\":\"gpt-4.1\""))

  let mut api_error = false
  let _ = parse_responses_transport_response(
    @gateway.OpenAIResponses,
    "gpt-4.1",
    { status: 500, body: "{\"error\":{\"message\":\"bad upstream\"}}" },
  ) catch {
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

  let translator = @gateway.create_responses_api_translator(
    @gateway.OpenAIResponses,
    response_id="resp_partial",
    model="gpt-4.1",
  )
  let acc = @openai.ResponsesApiAccumulator::new()
  let emitted : Array[String] = []
  let remaining = process_responses_stream_chunk(
    translator,
    acc,
    StructuredStreamValidator::new(None),
    "",
    @utf8.encode(
      "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}\n\nevent: response.completed",
    ),
    fn(event) { emitted.push(event.0) },
  )
  assert_true(remaining.contains("response.completed"))
  assert_eq(emitted, ["response.output_text.delta"])
  let flushed = process_responses_stream_chunk(
    translator,
    acc,
    StructuredStreamValidator::new(None),
    remaining,
    @utf8.encode("\ndata: {\"type\":\"response.completed\"}\n\n"),
    fn(event) { emitted.push(event.0) },
  )
  assert_eq(flushed, "")
  assert_eq(emitted, ["response.output_text.delta", "response.completed"])
  match acc.finish() {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected accumulated helper text from partial chunks")
  }
}

///|
async test "read_all_from_stream returns empty when the first read errors" {
  let reader = TimeoutStreamReader::new()
  let text = read_all_from_stream(reader)
  assert_eq(text, "")
}

///|
async test "chat_gateway: OpenAI CC invalid JSON raises ParseError" {
  let transport = MockTransport::new(200, "{")
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
    ClientError::ParseError(message) => {
      assert_true(message.contains("JSON parse error"))
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
async test "chat_gateway_responses maps sync transport failures to HttpError" {
  let transport = NetworkErrorTransport::new("offline")
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
  ) catch {
    ClientError::HttpError(message) => {
      assert_true(message.contains("Transport error: offline"))
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
async test "chat_gateway_responses maps sync transport timeout to HttpError" {
  let transport = TimeoutTransport::new()
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let mut caught = false
  let _result = chat_gateway_responses(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
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
async test "chat_gateway_responses_stream returns RateLimited on 429" {
  let transport = MockStreamingTransport::new(429, [])
  let provider = @gateway.ProviderConfig::new(
    "openai",
    @gateway.OpenAIResponses,
  )
  let result = chat_gateway_responses_stream(
    { ..provider, base_url: "https://api.openai.com/v1", api_key: "sk" },
    transport,
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [],
    "gpt-4.1",
    on_event=fn(_event) {  },
  )
  match result {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "rate_limit_error")
      assert_eq(failure.retry_after, Some(60))
    }
    _ => fail("Expected structured rate limit failure")
  }
}

///|
async test "chat_gateway_responses_stream maps request timeout to HttpError" {
  let transport = StreamingTimeoutTransport::new()
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
async test "chat_gateway_responses canonicalizes Gemini structured output" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"text":"```json
    #|{\"lookup_verification_url_response\":{\"content\":\"{\\\"url\\\":\\\"https://example.com/interop-check\\\"}\"}}
    #|```"}],"role":"model"}}]}
  let transport = MockTransport::new(200, body)
  let provider = @gateway.ProviderConfig::new(
    "gemini",
    @gateway.GoogleGenerativeAI,
  )
  let result = chat_gateway_responses(
    {
      ..provider,
      api_key: "test-key",
      base_url: "https://generativelanguage.googleapis.com/v1beta",
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
  ) catch {
    err => fail("Unexpected error: \{err}")
  }
  match result {
    @types.ModelResponse::Text(text) =>
      assert_eq(text, "{\"url\":\"https://example.com/interop-check\"}")
    _ => fail("Expected normalized Gemini text response")
  }
}
