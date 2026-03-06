///|
/// Responses API interoperability tests
/// Tests conversion between Responses API and various providers

// =============================================================================
// Responses API -> Anthropic Request Conversion
// =============================================================================

test "responses_to_anthropic: converts basic request" {
  let request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([{ "role": "user", "content": "Hello" }]),
    "max_output_tokens": 1024,
  }
  let result = @anthropic.responses_request_to_anthropic(request)
  match result {
    {
      "model": String(model),
      "messages": Array(msgs),
      "max_tokens": Number(max_tokens, ..),
      ..
    } => {
      assert_eq(model, "claude-sonnet-4-20250514")
      assert_eq(msgs.length(), 1)
      assert_eq(max_tokens.to_int(), 1024)
    }
    _ => fail("Unexpected result format")
  }
}

///|
test "responses_to_anthropic: converts tools" {
  let request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([{ "role": "user", "content": "What's the weather?" }]),
    "tools": Json::array([
      {
        "type": "function",
        "name": "get_weather",
        "description": "Get weather for a location",
        "parameters": {
          "type": "object",
          "properties": { "location": { "type": "string" } },
        },
      },
    ]),
  }
  let result = @anthropic.responses_request_to_anthropic(request)
  match result {
    { "tools": Array(tools), .. } => {
      assert_eq(tools.length(), 1)
      match tools[0] {
        { "name": String(name), "description": String(desc), .. } => {
          assert_eq(name, "get_weather")
          assert_eq(desc, "Get weather for a location")
        }
        _ => fail("Tool format mismatch")
      }
    }
    _ => fail("Missing tools in result")
  }
}

///|
test "responses_to_anthropic: converts web search builtin tool" {
  let request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([{ "role": "user", "content": "Search the web" }]),
    "tools": Json::array([
      { "type": "web_search_preview", "search_context_size": "medium" },
    ]),
  }
  let result = @anthropic.responses_request_to_anthropic(request)
  match result {
    { "tools": Array(tools), .. } =>
      match tools[0] {
        {
          "name": String(name),
          "input_schema": { "properties": Object(_), .. },
          ..
        } => assert_eq(name, "web_search")
        _ => fail("Expected web_search tool")
      }
    _ => fail("Missing tools in result")
  }
}

///|
test "responses_to_anthropic: converts function_call_output to tool_result" {
  let request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([
      { "role": "user", "content": "What's the weather?" },
      {
        "type": "function_call",
        "call_id": "fc_123",
        "name": "get_weather",
        "arguments": "{\"location\": \"Tokyo\"}",
      },
      {
        "type": "function_call_output",
        "call_id": "fc_123",
        "output": "Sunny, 25°C",
      },
    ]),
  }
  let result = @anthropic.responses_request_to_anthropic(request)
  match result {
    { "messages": Array(msgs), .. } =>
      // Should have: user message, assistant with tool_calls, tool result
      assert_true(msgs.length() >= 2)
    _ => fail("Unexpected format")
  }
}

// =============================================================================
// Anthropic Response -> Responses API Conversion
// =============================================================================

///|
test "anthropic_to_responses: converts text response" {
  let response : Json = {
    "id": "msg_123",
    "type": "message",
    "role": "assistant",
    "content": Json::array([{ "type": "text", "text": "Hello, world!" }]),
    "model": "claude-sonnet-4-20250514",
    "stop_reason": "end_turn",
  }
  let result = @anthropic.anthropic_response_to_responses(
    response,
    response_id="resp_123",
  )
  match result {
    { "id": String(id), "status": String(status), "output": Array(output), .. } => {
      assert_eq(id, "resp_123")
      assert_eq(status, "completed")
      assert_true(output.length() > 0)
      // Check message content
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Hello, world!")
            _ => fail("Content format mismatch")
          }
        _ => fail("Output format mismatch")
      }
    }
    _ => fail("Response format mismatch")
  }
}

///|
test "anthropic_to_responses: converts tool_use to function_call" {
  let response : Json = {
    "id": "msg_456",
    "type": "message",
    "role": "assistant",
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_01ABC123",
        "name": "get_weather",
        "input": { "location": "Tokyo" },
      },
    ]),
    "model": "claude-sonnet-4-20250514",
    "stop_reason": "tool_use",
  }
  let result = @anthropic.anthropic_response_to_responses(
    response,
    response_id="resp_456",
  )
  match result {
    { "output": Array(output), .. } => {
      assert_true(output.length() > 0)
      match output[0] {
        {
          "type": String("function_call"),
          "call_id": String(call_id),
          "name": String(name),
          ..
        } => {
          // ID should be converted from toolu_ to fc_
          assert_eq(call_id, "fc_01ABC123")
          assert_eq(name, "get_weather")
        }
        _ => fail("Function call format mismatch")
      }
    }
    _ => fail("Response format mismatch")
  }
}

///|
test "anthropic_to_responses: converts web_search tool_use to web_search_call" {
  let response : Json = {
    "id": "msg_web_1",
    "type": "message",
    "role": "assistant",
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_01WEB123",
        "name": "web_search",
        "input": { "query": "current weather in Tokyo" },
      },
    ]),
    "model": "claude-sonnet-4-20250514",
    "stop_reason": "tool_use",
  }
  let result = @anthropic.anthropic_response_to_responses(
    response,
    response_id="resp_web_1",
  )
  match result {
    { "output": Array(output), .. } =>
      match output[0] {
        {
          "type": String("web_search_call"),
          "action": { "query": String(query), .. },
          ..
        } => assert_eq(query, "current weather in Tokyo")
        _ => fail("Expected web_search_call")
      }
    _ => fail("Response format mismatch")
  }
}

// =============================================================================
// Responses API -> Gemini Conversion
// =============================================================================

///|
test "responses_to_gemini: converts basic request" {
  let request : Json = {
    "model": "gemini-2.0-flash",
    "input": Json::array([{ "role": "user", "content": "Hello" }]),
    "max_output_tokens": 2048,
  }
  let result = @gemini.responses_request_to_gemini(request)
  match result {
    { "contents": Array(contents), .. } => assert_true(contents.length() > 0)
    _ => fail("Missing contents")
  }
}

///|
test "responses_to_gemini: converts web search builtin tool" {
  let request : Json = {
    "model": "gemini-2.0-flash",
    "input": Json::array([{ "role": "user", "content": "Search the web" }]),
    "tools": Json::array([{ "type": "web_search_preview_2025_03_11" }]),
  }
  let result = @gemini.responses_request_to_gemini(request)
  match result {
    { "tools": Array(tools), .. } =>
      match tools[0] {
        { "functionDeclarations": Array(decls), .. } =>
          match decls[0] {
            { "name": String(name), .. } => assert_eq(name, "web_search")
            _ => fail("Expected function declaration")
          }
        _ => fail("Expected Gemini tools")
      }
    _ => fail("Missing Gemini tools")
  }
}

// =============================================================================
// Gemini Response -> Responses API Conversion
// =============================================================================

///|
test "gemini_to_responses: converts text response" {
  let response : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([{ "text": "Hello from Gemini!" }]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let result = @gemini.gemini_response_to_responses(
    response,
    response_id="resp_789",
    model="gemini-2.0-flash",
  )
  match result {
    { "id": String(id), "status": String(status), "output": Array(output), .. } => {
      assert_eq(id, "resp_789")
      assert_eq(status, "completed")
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "text": String(text), .. } =>
              assert_eq(text, "Hello from Gemini!")
            _ => fail("Content mismatch")
          }
        _ => fail("Output mismatch")
      }
    }
    _ => fail("Response mismatch")
  }
}

///|
test "gemini_to_responses: converts functionCall to function_call" {
  let response : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            {
              "functionCall": {
                "name": "get_weather",
                "args": { "location": "Tokyo" },
              },
            },
          ]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let result = @gemini.gemini_response_to_responses(
    response,
    response_id="resp_func",
    model="gemini-2.0-flash",
  )
  match result {
    { "output": Array(output), .. } =>
      match output[0] {
        {
          "type": String("function_call"),
          "name": String(name),
          "call_id": String(call_id),
          ..
        } => {
          assert_eq(name, "get_weather")
          // Gemini synthetic ID should be converted to fc_ format
          assert_true(call_id.has_prefix("fc_"))
        }
        _ => fail("Function call mismatch")
      }
    _ => fail("Response mismatch")
  }
}

///|
test "gemini_to_responses: converts web_search functionCall to web_search_call" {
  let response : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            {
              "functionCall": {
                "name": "web_search",
                "args": { "query": "latest TypeScript features" },
              },
            },
          ]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let result = @gemini.gemini_response_to_responses(
    response,
    response_id="resp_web_gemini",
    model="gemini-2.0-flash",
  )
  match result {
    { "output": Array(output), .. } =>
      match output[0] {
        {
          "type": String("web_search_call"),
          "action": { "query": String(query), .. },
          ..
        } => assert_eq(query, "latest TypeScript features")
        _ => fail("Expected web_search_call")
      }
    _ => fail("Response mismatch")
  }
}

// =============================================================================
// Full Pipeline: Responses API -> Provider -> Responses API
// =============================================================================

///|
test "full_pipeline: anthropic roundtrip preserves tool call IDs" {
  // 1. Original Responses API request with tool call
  let original_call_id = "fc_original_123"
  // 2. Simulated Anthropic response (ID would be converted)
  let anthropic_response : Json = {
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_original_123", // Same suffix, different prefix
        "name": "test_tool",
        "input": {},
      },
    ]),
    "model": "claude-sonnet-4-20250514",
    "stop_reason": "tool_use",
  }
  // 3. Convert back to Responses API
  let responses_result = @anthropic.anthropic_response_to_responses(
    anthropic_response,
    response_id="resp_test",
  )
  // 4. Verify ID suffix is preserved
  match responses_result {
    { "output": Array(output), .. } =>
      match output[0] {
        { "call_id": String(call_id), .. } =>
          // The suffix should be preserved through conversion
          assert_true(@util.is_same_tool_call_id(original_call_id, call_id))
        _ => fail("Missing call_id")
      }
    _ => fail("Missing output")
  }
}
