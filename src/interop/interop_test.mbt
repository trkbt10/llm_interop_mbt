///|
/// Interop package tests

// Test fixtures
let test_response_id : String = "resp_001"

///|
let test_model : String = "gpt-4"

///|
let test_model_harmony : String = "openai/gpt-oss-20b"

// =============================================================================
// Responses API Input -> Messages Tests
// =============================================================================

///|
test "responses_input_to_messages: basic user message" {
  let input : Array[Json] = [
    { "role": "system", "content": "You are helpful." },
    { "role": "user", "content": "Hello" },
  ]
  let messages = responses_input_to_messages(input)
  inspect(messages.length(), content="2")
  match messages[0] {
    @types.ModelMessage::System(content) =>
      inspect(content, content="You are helpful.")
    _ => fail("Expected System message")
  }
  match messages[1] {
    @types.ModelMessage::User(content~, ..) => inspect(content, content="Hello")
    _ => fail("Expected User message")
  }
}

///|
test "responses_input_to_messages: function_call and output" {
  let input : Array[Json] = [
    { "role": "user", "content": "What time is it?" },
    {
      "type": "function_call",
      "call_id": "fc_123",
      "name": "datetime",
      "arguments": "{}",
      "status": "completed",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_123",
      "output": "{\"time\":\"15:00\"}",
    },
  ]
  let messages = responses_input_to_messages(input)
  inspect(messages.length(), content="3")
  // User message
  match messages[0] {
    @types.ModelMessage::User(content~, ..) =>
      inspect(content, content="What time is it?")
    _ => fail("Expected User message")
  }
  // Assistant with tool call
  match messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="fc_123")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected Assistant message with tool_calls")
  }
  // Tool result
  match messages[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
      inspect(tool_call_id, content="fc_123")
      inspect(content, content="{\"time\":\"15:00\"}")
    }
    _ => fail("Expected ToolResult message")
  }
}

///|
test "responses_input_to_messages: multiple parallel tool calls" {
  let input : Array[Json] = [
    { "role": "user", "content": "Get time and weather" },
    {
      "type": "function_call",
      "call_id": "fc_time",
      "name": "datetime",
      "arguments": "{}",
    },
    {
      "type": "function_call",
      "call_id": "fc_weather",
      "name": "weather",
      "arguments": "{\"city\":\"Tokyo\"}",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_time",
      "output": "{\"time\":\"15:00\"}",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_weather",
      "output": "{\"temp\":\"20C\"}",
    },
  ]
  let messages = responses_input_to_messages(input)
  // Should be: User, Assistant(2 tool_calls), ToolResult, ToolResult
  inspect(messages.length(), content="4")
  // User
  match messages[0] {
    @types.ModelMessage::User(content~, ..) =>
      inspect(content, content="Get time and weather")
    _ => fail("Expected User")
  }
  // Assistant with 2 tool calls
  match messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      inspect(calls.length(), content="2")
      inspect(calls[0].name, content="datetime")
      inspect(calls[1].name, content="weather")
    }
    _ => fail("Expected Assistant with 2 tool_calls")
  }
}

// =============================================================================
// ModelResponse -> Responses API JSON Tests
// =============================================================================

///|
test "model_response_to_responses_json: text response" {
  let response = @types.ModelResponse::Text("Hello, world!")
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "id": String(id), "output": Array(output), .. } => {
      assert_eq(id, test_response_id)
      inspect(output.length(), content="1")
      match output[0] {
        { "type": String("message"), "content": Array(content_arr), .. } =>
          match content_arr[0] {
            { "type": String("output_text"), "text": String(t), .. } =>
              inspect(t, content="Hello, world!")
            _ => fail("Expected output_text")
          }
        _ => fail("Expected message output")
      }
    }
    _ => fail("Expected valid response JSON")
  }
}

///|
test "model_response_to_responses_json: tool calls" {
  let calls : Array[@types.ToolCallRequest] = [
    @types.ToolCallRequest::new(id="fc_001", name="datetime", arguments={
      "tz": "UTC",
    }),
  ]
  let response = @types.ModelResponse::ToolCalls(calls)
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "output": Array(output), .. } => {
      inspect(output.length(), content="1")
      match output[0] {
        {
          "type": String("function_call"),
          "name": String(name),
          "call_id": String(call_id),
          ..
        } => {
          inspect(name, content="datetime")
          inspect(call_id, content="fc_001")
        }
        _ => fail("Expected function_call output")
      }
    }
    _ => fail("Expected valid response JSON")
  }
}

// =============================================================================
// Harmony -> Responses API Translator Tests
// =============================================================================

///|
test "HarmonyToResponsesTranslator: text streaming" {
  let translator = HarmonyToResponsesTranslator::new(
    response_id=test_response_id,
  )
  // First chunk with role
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  let events1 = translator.translate(event1)
  // Should emit response.created
  inspect(events1.length(), content="1")
  inspect(events1[0].0, content="response.created")
  // Content chunk
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([{ "index": 0, "delta": { "content": "Hello" } }]),
    },
  }
  let events2 = translator.translate(event2)
  inspect(events2.length(), content="1")
  inspect(events2[0].0, content="response.output_text.delta")
  // Final chunk with stop
  let event3 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "stop" },
      ]),
    },
  }
  let events3 = translator.translate(event3)
  // Should emit output_text.done and completed
  inspect(events3.length(), content="2")
  inspect(events3[0].0, content="response.output_text.done")
  inspect(events3[1].0, content="response.completed")
}

///|
test "HarmonyToResponsesTranslator: tool call streaming" {
  let translator = HarmonyToResponsesTranslator::new(
    response_id=test_response_id,
  )
  // First chunk
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  ignore(translator.translate(event1))
  // Tool call chunk
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": {
            "tool_calls": Json::array([
              {
                "id": "fc_xyz",
                "type": "function",
                "function": { "name": "datetime", "arguments": "{}" },
              },
            ]),
          },
        },
      ]),
    },
  }
  let events2 = translator.translate(event2)
  // Should emit output_item.added and arguments.delta
  let mut found_added = false
  for e in events2 {
    if e.0 == "response.output_item.added" {
      found_added = true
    }
  }
  inspect(found_added, content="true")
}

// =============================================================================
// Round-trip Tests
// =============================================================================

///|
test "responses_request_to_chat_completions: basic request" {
  let request : Json = {
    "model": Json::string(test_model_harmony),
    "input": Json::array([
      { "role": "system", "content": "You are helpful." },
      { "role": "user", "content": "Hello" },
    ]),
  }
  let chat_request = responses_request_to_chat_completions(request)
  match chat_request {
    { "model": String(model), "messages": Array(msgs), "stream": True, .. } => {
      assert_eq(model, test_model_harmony)
      inspect(msgs.length(), content="2")
    }
    _ => fail("Expected valid Chat Completions request")
  }
}

///|
test "responses_request_to_chat_completions: with tools" {
  let request : Json = {
    "model": Json::string(test_model_harmony),
    "input": Json::array([{ "role": "user", "content": "What time?" }]),
    "tools": Json::array([
      {
        "type": "function",
        "function": {
          "name": "datetime",
          "description": "Get time",
          "parameters": {},
        },
      },
    ]),
    "tool_choice": "auto",
  }
  let chat_request = responses_request_to_chat_completions(request)
  match chat_request {
    { "tools": Array(tools), "tool_choice": String(choice), .. } => {
      inspect(tools.length(), content="1")
      inspect(choice, content="auto")
    }
    _ => fail("Expected tools in request")
  }
}

// =============================================================================
// Tool Call ID Conversion Tests
// =============================================================================

///|
test "detect_tool_call_id_provider: OpenAI Chat Completions format" {
  let provider = detect_tool_call_id_provider("call_abc123")
  match provider {
    ToolCallIdProvider::OpenAIChatCompletions => ()
    _ => fail("Expected OpenAIChatCompletions")
  }
}

///|
test "detect_tool_call_id_provider: OpenAI Responses API format" {
  let provider = detect_tool_call_id_provider("fc_abc123")
  match provider {
    ToolCallIdProvider::OpenAIResponsesApi => ()
    _ => fail("Expected OpenAIResponsesApi")
  }
}

///|
test "detect_tool_call_id_provider: Anthropic Claude format" {
  let provider = detect_tool_call_id_provider("toolu_abc123")
  match provider {
    ToolCallIdProvider::AnthropicClaude => ()
    _ => fail("Expected AnthropicClaude")
  }
}

///|
test "detect_tool_call_id_provider: Google Gemini format" {
  let provider = detect_tool_call_id_provider("gemini_search_0")
  match provider {
    ToolCallIdProvider::GoogleGemini => ()
    _ => fail("Expected GoogleGemini")
  }
}

///|
test "detect_tool_call_id_provider: Unknown format" {
  let provider = detect_tool_call_id_provider("random_id")
  match provider {
    ToolCallIdProvider::Unknown => ()
    _ => fail("Expected Unknown")
  }
}

///|
test "anthropic_to_openai_chat_call_id: toolu_xxx -> call_xxx" {
  let result = anthropic_to_openai_chat_call_id("toolu_abc123")
  inspect(result, content="call_abc123")
}

///|
test "gemini_to_openai_chat_call_id: gemini_xxx -> call_xxx" {
  let result = gemini_to_openai_chat_call_id("gemini_search_0")
  inspect(result, content="call_search_0")
}

///|
test "openai_chat_to_anthropic_tool_use_id: call_xxx -> toolu_xxx" {
  let result = openai_chat_to_anthropic_tool_use_id("call_xyz789")
  inspect(result, content="toolu_xyz789")
}

///|
test "anthropic_to_openai_responses_call_id: toolu_xxx -> fc_xxx" {
  let result = anthropic_to_openai_responses_call_id("toolu_test123")
  inspect(result, content="fc_test123")
}

///|
test "openai_chat_to_openai_responses_call_id: call_xxx -> fc_xxx" {
  let result = openai_chat_to_openai_responses_call_id("call_test456")
  inspect(result, content="fc_test456")
}

///|
test "is_same_tool_call_id: same suffix different prefix" {
  let openai_chat_id = "call_abc123"
  let anthropic_id = "toolu_abc123"
  inspect(is_same_tool_call_id(openai_chat_id, anthropic_id), content="true")
}

///|
test "is_same_tool_call_id: different suffix returns false" {
  let id1 = "call_abc"
  let id2 = "call_xyz"
  inspect(is_same_tool_call_id(id1, id2), content="false")
}

///|
test "is_same_tool_call_id: cross-provider comparison" {
  let openai_chat_id = "call_weather_1"
  let anthropic_id = "toolu_weather_1"
  let openai_responses_id = "fc_weather_1"
  inspect(is_same_tool_call_id(openai_chat_id, anthropic_id), content="true")
  inspect(
    is_same_tool_call_id(openai_chat_id, openai_responses_id),
    content="true",
  )
  inspect(
    is_same_tool_call_id(anthropic_id, openai_responses_id),
    content="true",
  )
}

///|
test "convert_tool_call_request_ids: to Anthropic Claude format" {
  let requests = [
    @types.ToolCallRequest::new(id="call_123", name="search", arguments={
      "q": "test",
    }),
    @types.ToolCallRequest::new(id="call_456", name="fetch", arguments={
      "url": "http://example.com",
    }),
  ]
  let converted = convert_tool_call_request_ids(
    requests,
    ToolCallIdProvider::AnthropicClaude,
  )
  inspect(converted[0].id, content="toolu_123")
  inspect(converted[1].id, content="toolu_456")
  // Names and arguments should be preserved
  inspect(converted[0].name, content="search")
  inspect(converted[1].name, content="fetch")
}

///|
test "convert_message_tool_call_ids: converts Assistant and ToolResult" {
  let messages = [
    @types.ModelMessage::User(content="Hello", name=None),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="call_abc", name="test", arguments={}),
      ]),
    ),
    @types.ModelMessage::ToolResult(tool_call_id="call_abc", content="result"),
  ]
  let converted = convert_message_tool_call_ids(
    messages,
    ToolCallIdProvider::AnthropicClaude,
  )
  // User message unchanged
  match converted[0] {
    @types.ModelMessage::User(..) => ()
    _ => fail("Expected User message")
  }
  // Assistant tool_calls converted
  match converted[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
      inspect(calls[0].id, content="toolu_abc")
    _ => fail("Expected Assistant with tool_calls")
  }
  // ToolResult ID converted
  match converted[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, ..) =>
      inspect(tool_call_id, content="toolu_abc")
    _ => fail("Expected ToolResult")
  }
}

///|
test "generate_gemini_tool_call_id: creates gemini_<name>_<index> format" {
  let id = generate_gemini_tool_call_id("get_weather", 0)
  inspect(id, content="gemini_get_weather_0")
}

///|
test "generate_openai_chat_call_id: increments counter" {
  reset_tool_call_id_counter()
  let id1 = generate_openai_chat_call_id()
  let id2 = generate_openai_chat_call_id()
  inspect(id1, content="call_1")
  inspect(id2, content="call_2")
}

///|
test "generate_anthropic_tool_use_id: uses counter" {
  reset_tool_call_id_counter()
  let id = generate_anthropic_tool_use_id()
  inspect(id, content="toolu_1")
}

///|
test "ToolCallIdProvider::prefix returns correct prefix" {
  inspect(ToolCallIdProvider::OpenAIChatCompletions.prefix(), content="call_")
  inspect(ToolCallIdProvider::OpenAIResponsesApi.prefix(), content="fc_")
  inspect(ToolCallIdProvider::AnthropicClaude.prefix(), content="toolu_")
  inspect(ToolCallIdProvider::GoogleGemini.prefix(), content="gemini_")
}

///|
test "ToolCallIdFormat: has_native_id correctly set" {
  let openai_format = ToolCallIdProvider::OpenAIChatCompletions.format()
  let gemini_format = ToolCallIdProvider::GoogleGemini.format()
  inspect(openai_format.has_native_id, content="true")
  inspect(gemini_format.has_native_id, content="false")
}
