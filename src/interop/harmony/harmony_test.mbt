///|
/// Harmony package tests

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
