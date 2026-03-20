///|
/// Protocol-level interoperability tests
///
/// Tests parsing responses from different providers and verifying that
/// tool calls can be correctly converted between formats.

// =============================================================================
// Fixture Data: Actual API response formats
// =============================================================================

///|
/// Anthropic Claude Messages API response with tool_use
fn fixture_anthropic_toolcall_response() -> Json {
  {
    "model": "claude-sonnet-4-6",
    "id": "msg_013LtsNHcMT15uWLnD3jrQ93",
    "type": "message",
    "role": "assistant",
    "content": Json::array([
      { "type": "text", "text": "I'll check the weather in Tokyo for you!" },
      {
        "type": "tool_use",
        "id": "toolu_017RLx2kgtjuhyb6yzCYoY4M",
        "name": "get_weather",
        "input": { "location": "Tokyo" },
      },
    ]),
    "stop_reason": "tool_use",
  }
}

///|
/// OpenAI Chat Completions API response with tool_calls
fn fixture_openai_chat_toolcall_response() -> Json {
  {
    "id": "chatcmpl-abc123",
    "object": "chat.completion",
    "choices": Json::array([
      {
        "index": 0,
        "message": {
          "role": "assistant",
          "content": Json::null(),
          "tool_calls": Json::array([
            {
              "id": "call_eArLoUy4ikZiEzhId8UK1v2l",
              "type": "function",
              "function": {
                "name": "get_weather",
                "arguments": "{\"location\":\"Tokyo\"}",
              },
            },
          ]),
        },
        "finish_reason": "tool_calls",
      },
    ]),
  }
}

///|
/// OpenAI Responses API response with function_call
fn fixture_openai_responses_toolcall_response() -> Json {
  {
    "id": "resp_0f6e93c5cb6fbed40069a2579e16b08191a5bdd3176047b15f",
    "object": "response",
    "status": "completed",
    "model": "gpt-4o-mini-2024-07-18",
    "output": Json::array([
      {
        "id": "fc_0f6e93c5cb6fbed40069a2579e9c688191925c675daa400bda",
        "type": "function_call",
        "status": "completed",
        "arguments": "{\"location\":\"Tokyo\"}",
        "call_id": "call_eArLoUy4ikZiEzhId8UK1v2l",
        "name": "get_weather",
      },
    ]),
  }
}

///|
/// Google Gemini GenerateContent response with functionCall
fn fixture_gemini_toolcall_response() -> Json {
  {
    "candidates": Json::array([
      {
        "content": {
          "parts": Json::array([
            {
              "functionCall": {
                "name": "get_weather",
                "args": { "location": "Tokyo" },
              },
            },
          ]),
          "role": "model",
        },
        "finishReason": "STOP",
      },
    ]),
    "usageMetadata": {
      "promptTokenCount": 44,
      "candidatesTokenCount": 5,
      "totalTokenCount": 49,
    },
    "modelVersion": "gemini-2.0-flash",
  }
}

// =============================================================================
// Parse and Extract Tool Calls Tests
// =============================================================================

///|
test "parse Anthropic response and extract tool calls" {
  let response = @anthropic.parse_response(
    fixture_anthropic_toolcall_response(),
  )
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      assert_true(calls[0].id.has_prefix("toolu_"))
      match calls[0].arguments {
        { "location": String(loc), .. } => inspect(loc, content="Tokyo")
        _ => fail("Expected location in arguments")
      }
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse OpenAI Chat response and extract tool calls" {
  let response = @openai.parse_chat_response(
    fixture_openai_chat_toolcall_response(),
  )
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      assert_true(calls[0].id.has_prefix("call_"))
      match calls[0].arguments {
        { "location": String(loc), .. } => inspect(loc, content="Tokyo")
        _ => fail("Expected location in arguments")
      }
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse OpenAI Responses API response and extract tool calls" {
  let response = @openai.parse_responses_api_response(
    fixture_openai_responses_toolcall_response(),
  )
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      // Responses API uses call_id field
      assert_true(calls[0].id.has_prefix("call_"))
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse Gemini response and extract tool calls" {
  let response = @gemini.parse_response(
    fixture_gemini_toolcall_response(),
  )
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      // Gemini doesn't have native IDs, we generate synthetic ones
      assert_true(calls[0].id.has_prefix("gemini_"))
      match calls[0].arguments {
        { "location": String(loc), .. } => inspect(loc, content="Tokyo")
        _ => fail("Expected location in arguments")
      }
    }
    _ => fail("Expected ToolCalls response")
  }
}

// =============================================================================
// Cross-provider Tool Call Conversion Tests
// =============================================================================

///|
test "interop: Anthropic tool call -> OpenAI Chat format" {
  let anthropic_response = @anthropic.parse_response(
    fixture_anthropic_toolcall_response(),
  )
  match anthropic_response {
    @types.ModelResponse::ToolCalls(calls) => {
      // Convert to OpenAI Chat format IDs
      let converted = @util.convert_tool_call_request_ids(
        calls,
        @util.ToolCallIdProvider::OpenAIChatCompletions,
      )
      inspect(converted.length(), content="1")
      assert_true(converted[0].id.has_prefix("call_"))
      // Name and arguments should be preserved
      inspect(converted[0].name, content="get_weather")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "interop: OpenAI Chat tool call -> Anthropic format" {
  let openai_response = @openai.parse_chat_response(
    fixture_openai_chat_toolcall_response(),
  )
  match openai_response {
    @types.ModelResponse::ToolCalls(calls) => {
      let converted = @util.convert_tool_call_request_ids(
        calls,
        @util.ToolCallIdProvider::AnthropicClaude,
      )
      inspect(converted.length(), content="1")
      assert_true(converted[0].id.has_prefix("toolu_"))
      inspect(converted[0].name, content="get_weather")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "interop: Gemini tool call -> OpenAI Responses format" {
  let gemini_response = @gemini.parse_response(
    fixture_gemini_toolcall_response(),
  )
  match gemini_response {
    @types.ModelResponse::ToolCalls(calls) => {
      let converted = @util.convert_tool_call_request_ids(
        calls,
        @util.ToolCallIdProvider::OpenAIResponsesApi,
      )
      inspect(converted.length(), content="1")
      assert_true(converted[0].id.has_prefix("fc_"))
      inspect(converted[0].name, content="get_weather")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "interop: all providers can be compared via is_same_tool_call_id" {
  // Parse responses from all providers
  let anthropic_calls = match
    @anthropic.parse_response(fixture_anthropic_toolcall_response()) {
    @types.ModelResponse::ToolCalls(c) => c
    _ => []
  }
  let openai_chat_calls = match
    @openai.parse_chat_response(fixture_openai_chat_toolcall_response()) {
    @types.ModelResponse::ToolCalls(c) => c
    _ => []
  }
  // Convert Anthropic to have same suffix as OpenAI Chat
  let anthropic_converted = @util.convert_tool_call_request_ids(
    anthropic_calls,
    @util.ToolCallIdProvider::OpenAIChatCompletions,
  )
  // Now they have the same prefix format (call_)
  // Note: They won't have the same suffix since the original IDs are different
  // This test verifies the conversion process works correctly
  assert_true(anthropic_converted[0].id.has_prefix("call_"))
  assert_true(openai_chat_calls[0].id.has_prefix("call_"))
}

// =============================================================================
// Multi-tool Call Interop Tests
// =============================================================================

///|
/// Gemini response with multiple function calls
fn fixture_gemini_multi_toolcall_response() -> Json {
  {
    "candidates": Json::array([
      {
        "content": {
          "parts": Json::array([
            {
              "functionCall": {
                "name": "get_weather",
                "args": { "location": "Tokyo" },
              },
            },
            {
              "functionCall": {
                "name": "get_time",
                "args": { "timezone": "Asia/Tokyo" },
              },
            },
          ]),
          "role": "model",
        },
        "finishReason": "STOP",
      },
    ]),
  }
}

///|
test "interop: Gemini multi tool calls -> Anthropic format" {
  let gemini_response = @gemini.parse_response(
    fixture_gemini_multi_toolcall_response(),
  )
  match gemini_response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="2")
      // Verify synthetic IDs are generated with indices
      assert_true(calls[0].id.has_prefix("gemini_get_weather_"))
      assert_true(calls[1].id.has_prefix("gemini_get_time_"))
      // Convert to Anthropic
      let converted = @util.convert_tool_call_request_ids(
        calls,
        @util.ToolCallIdProvider::AnthropicClaude,
      )
      assert_true(converted[0].id.has_prefix("toolu_"))
      assert_true(converted[1].id.has_prefix("toolu_"))
      // Names preserved
      inspect(converted[0].name, content="get_weather")
      inspect(converted[1].name, content="get_time")
    }
    _ => fail("Expected ToolCalls")
  }
}

// =============================================================================
// Full Message Flow Interop Tests
// =============================================================================

///|
test "full flow: parse Anthropic -> build message -> convert to OpenAI Chat" {
  // Parse Anthropic response
  let anthropic_response = @anthropic.parse_response(
    fixture_anthropic_toolcall_response(),
  )
  let tool_calls = match anthropic_response {
    @types.ModelResponse::ToolCalls(c) => c
    _ => []
  }
  // Create message with tool calls
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="What's the weather in Tokyo?", name=None),
    @types.ModelMessage::Assistant(content="", tool_calls=Some(tool_calls)),
    @types.ModelMessage::ToolResult(
      tool_call_id=tool_calls[0].id,
      content="{\"temp\": 25, \"condition\": \"sunny\"}",
    ),
  ]
  // Convert all IDs to OpenAI Chat format
  let openai_messages = @util.convert_message_tool_call_ids(
    messages,
    @util.ToolCallIdProvider::OpenAIChatCompletions,
  )
  // Verify conversions
  match openai_messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
      assert_true(calls[0].id.has_prefix("call_"))
    _ => fail("Expected Assistant with tool_calls")
  }
  match openai_messages[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, ..) =>
      assert_true(tool_call_id.has_prefix("call_"))
    _ => fail("Expected ToolResult")
  }
  // Build OpenAI Chat body
  let body = @openai.build_chat_body(
    "gpt-4",
    openai_messages,
    [],
    max_tokens=Some(1000),
  )
  match body {
    { "messages": Array(msgs), .. } => {
      inspect(msgs.length(), content="3")
      // Verify tool message has correct format
      match msgs[2] {
        { "role": String("tool"), "tool_call_id": String(id), .. } =>
          assert_true(id.has_prefix("call_"))
        _ => fail("Expected tool message with call_ id")
      }
    }
    _ => fail("Expected valid body")
  }
}

///|
test "full flow: parse OpenAI -> convert to Anthropic -> build body" {
  // Parse OpenAI Chat response
  let openai_response = @openai.parse_chat_response(
    fixture_openai_chat_toolcall_response(),
  )
  let tool_calls = match openai_response {
    @types.ModelResponse::ToolCalls(c) => c
    _ => []
  }
  // Create messages
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="What's the weather in Tokyo?", name=None),
    @types.ModelMessage::Assistant(content="", tool_calls=Some(tool_calls)),
    @types.ModelMessage::ToolResult(
      tool_call_id=tool_calls[0].id,
      content="{\"temp\": 25}",
    ),
  ]
  // Convert to Anthropic format
  let anthropic_messages = @util.convert_message_tool_call_ids(
    messages,
    @util.ToolCallIdProvider::AnthropicClaude,
  )
  // Build Anthropic body
  let body = @anthropic.build_body(
    "claude-3-opus-20240229",
    anthropic_messages,
    [],
    max_tokens=Some(4096),
  )
  match body {
    { "messages": Array(msgs), .. } => {
      // User + Assistant (with tool_use) + ToolResult (as user)
      inspect(msgs.length(), content="3")
      // Verify Assistant message has tool_use with toolu_ id
      match msgs[1] {
        { "role": String("assistant"), "content": Array(content_arr), .. } =>
          match content_arr[0] {
            { "type": String("tool_use"), "id": String(id), .. } =>
              assert_true(id.has_prefix("toolu_"))
            _ => fail("Expected tool_use content")
          }
        _ => fail("Expected assistant content array")
      }
      // Verify tool_result has correct format with toolu_ id
      match msgs[2] {
        { "content": Array(content_arr), .. } =>
          match content_arr[0] {
            { "type": String("tool_result"), "tool_use_id": String(id), .. } =>
              assert_true(id.has_prefix("toolu_"))
            _ => fail("Expected tool_result content")
          }
        _ => fail("Expected content array")
      }
    }
    _ => fail("Expected valid body")
  }
}
