///|
/// Fixture-based interoperability tests
/// Tests with real API response fixtures from llm-interop TypeScript

// =============================================================================
// Claude Message Fixtures (from __mocks__/raw/claude/message-sync.jsonl)
// =============================================================================

///|
/// Claude text response fixture
fn claude_text_response_fixture() -> String {
  (
    #|{"id":"msg_01H4EZ7bVBmGFXNVbfCjZ3Qq","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Hello! I'm doing well, thank you for asking."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":14,"output_tokens":39}}
  )
}

///|
/// Claude tool_use response fixture
fn claude_tool_use_fixture() -> String {
  (
    #|{"id":"msg_01Dd5mpz82b2DqwPfXJfScob","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"I'll check the current weather in Tokyo for you."},{"type":"tool_use","id":"toolu_01FcyP8aupV3XbyLGkWCk6ud","name":"get_weather","input":{"location":"Tokyo, Japan"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":428,"output_tokens":67}}
  )
}

///|
/// Claude multi-tool response fixture
fn claude_multi_tool_fixture() -> String {
  (
    #|{"id":"msg_015LTG5S94Pp1SFBZRAE1D4t","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"I'll help you get the weather information for NYC and calculate 42 * 17."},{"type":"tool_use","id":"toolu_01MtRPq7UMosxg6kJJzp578j","name":"get_weather","input":{"location":"New York City, NY"}},{"type":"tool_use","id":"toolu_019fGTP4hGy1RMB5DiQQLBrH","name":"calculate","input":{"expression":"42 * 17"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":508,"output_tokens":115}}
  )
}

///|
/// Claude tool result continuation fixture
fn claude_tool_result_continuation_fixture() -> String {
  let s =
    #|{"id":"msg_01TiDRTVnboWmQNMMHQDmKPU","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"The current weather in London, UK is: Temperature 8C, Condition Cloudy, Humidity 82 percent, Wind Speed 12 km/h. It is a fairly cool and humid day in London with cloudy skies and moderate wind."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":538,"output_tokens":67}}
  s
}

// =============================================================================
// OpenAI Responses API Fixtures (from __mocks__/raw/openai/responses-sync.jsonl)
// =============================================================================

///|
/// OpenAI Responses API text response fixture (unused for now, kept for future tests)
fn _openai_responses_text_fixture() -> String {
  let s =
    #|{"id":"resp_68aeb42791d0819f8002ba1431f24e7a","object":"response","created_at":1756279847,"status":"completed","model":"gpt-5-mini-2025-08-07","output":[{"id":"msg_68aeb42b4538819fa09142f60c5e6da1","type":"message","status":"completed","content":[{"type":"output_text","text":"Hi there! How can I help you today?"}],"role":"assistant"}],"usage":{"input_tokens":18,"output_tokens":209,"total_tokens":227}}
  s
}

// =============================================================================
// Test: Parse Claude Fixtures and Convert to Responses API
// =============================================================================

///|
test "fixture: parse Claude text response" {
  let json = @json.parse(claude_text_response_fixture()) catch {
    err => {
      fail("Failed to parse fixture: " + err.to_string())
      return
    }
  }
  let result = anthropic_response_to_responses(json, response_id="resp_test")
  match result {
    { "status": String("completed"), "output": Array(output), .. } => {
      assert_true(output.length() > 0)
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_true(text.has_prefix("Hello!"))
            _ => fail("Content format mismatch")
          }
        _ => fail("Output format mismatch")
      }
    }
    _ => fail("Response format mismatch")
  }
}

///|
test "fixture: parse Claude tool_use and convert to Responses API" {
  let json = @json.parse(claude_tool_use_fixture()) catch {
    err => {
      fail("Failed to parse fixture: " + err.to_string())
      return
    }
  }
  let result = anthropic_response_to_responses(json, response_id="resp_test")
  match result {
    { "output": Array(output), .. } => {
      // Should have message + function_call
      assert_true(output.length() >= 1)
      // Find function_call
      let mut found_function_call = false
      for item in output {
        match item {
          {
            "type": String("function_call"),
            "name": String(name),
            "call_id": String(call_id),
            ..
          } => {
            assert_eq(name, "get_weather")
            // ID should be converted from toolu_ to fc_
            assert_true(call_id.has_prefix("fc_"))
            assert_true(
              is_same_tool_call_id("toolu_01FcyP8aupV3XbyLGkWCk6ud", call_id),
            )
            found_function_call = true
          }
          _ => ()
        }
      }
      assert_true(found_function_call)
    }
    _ => fail("Response format mismatch")
  }
}

///|
test "fixture: parse Claude multi-tool and convert to Responses API" {
  let json = @json.parse(claude_multi_tool_fixture()) catch {
    err => {
      fail("Failed to parse fixture: " + err.to_string())
      return
    }
  }
  let result = anthropic_response_to_responses(json, response_id="resp_test")
  match result {
    { "output": Array(output), .. } => {
      // Count function calls
      let mut function_call_count = 0
      let mut found_weather = false
      let mut found_calculate = false
      for item in output {
        match item {
          { "type": String("function_call"), "name": String(name), .. } => {
            function_call_count = function_call_count + 1
            if name == "get_weather" {
              found_weather = true
            }
            if name == "calculate" {
              found_calculate = true
            }
          }
          _ => ()
        }
      }
      assert_eq(function_call_count, 2)
      assert_true(found_weather)
      assert_true(found_calculate)
    }
    _ => fail("Response format mismatch")
  }
}

// =============================================================================
// Test: Multi-turn Conversation
// =============================================================================

///|
test "multi-turn: user -> assistant -> tool_result -> assistant" {
  // Step 1: User asks about weather
  let user_request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([
      { "role": "user", "content": "What's the weather in Tokyo?" },
    ]),
    "tools": Json::array([
      {
        "type": "function",
        "name": "get_weather",
        "description": "Get weather",
        "parameters": {
          "type": "object",
          "properties": { "location": { "type": "string" } },
        },
      },
    ]),
  }
  // Convert to Anthropic format
  let anthropic_req = responses_request_to_anthropic(user_request)
  match anthropic_req {
    { "messages": Array(msgs), "tools": Array(tools), .. } => {
      assert_eq(msgs.length(), 1)
      assert_eq(tools.length(), 1)
    }
    _ => fail("Request conversion failed")
  }
  // Step 2: Anthropic responds with tool_use
  let anthropic_response = @json.parse(claude_tool_use_fixture()) catch {
    _ => {
      fail("Failed to parse fixture")
      return
    }
  }
  let responses_result = anthropic_response_to_responses(
    anthropic_response,
    response_id="resp_1",
  )
  // Extract call_id for tool result
  let mut tool_call_id = ""
  match responses_result {
    { "output": Array(output), .. } =>
      for item in output {
        match item {
          { "type": String("function_call"), "call_id": String(cid), .. } =>
            tool_call_id = cid
          _ => ()
        }
      }
    _ => ()
  }
  assert_true(tool_call_id.length() > 0)
  // Step 3: Build request with tool result
  let followup_request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([
      { "role": "user", "content": "What's the weather in Tokyo?" },
      {
        "type": "function_call",
        "call_id": tool_call_id,
        "name": "get_weather",
        "arguments": "{\"location\": \"Tokyo, Japan\"}",
      },
      {
        "type": "function_call_output",
        "call_id": tool_call_id,
        "output": "Sunny, 22°C",
      },
    ]),
  }
  let anthropic_req2 = responses_request_to_anthropic(followup_request)
  match anthropic_req2 {
    { "messages": Array(msgs), .. } =>
      // Should have: user message, assistant with tool_calls, tool result
      assert_true(msgs.length() >= 2)
    _ => fail("Followup request conversion failed")
  }
  // Step 4: Anthropic responds with final answer
  let final_response = @json.parse(claude_tool_result_continuation_fixture()) catch {
    _ => {
      fail("Failed to parse fixture")
      return
    }
  }
  let final_result = anthropic_response_to_responses(
    final_response,
    response_id="resp_2",
  )
  match final_result {
    { "output": Array(output), .. } =>
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "text": String(text), .. } =>
              assert_true(text.contains("London") || text.contains("weather"))
            _ => fail("Content mismatch")
          }
        _ => fail("Output mismatch")
      }
    _ => fail("Final response mismatch")
  }
}

// =============================================================================
// Test: Tool Call ID Preservation Through Multi-turn
// =============================================================================

///|
test "multi-turn: tool call ID preserved through conversation" {
  let original_claude_id = "toolu_01FcyP8aupV3XbyLGkWCk6ud"
  // Claude responds with tool_use
  let anthropic_response = @json.parse(claude_tool_use_fixture()) catch {
    _ => {
      fail("Failed to parse")
      return
    }
  }
  // Convert to Responses API
  let responses_result = anthropic_response_to_responses(
    anthropic_response,
    response_id="resp_1",
  )
  // Extract the converted ID
  let mut responses_call_id = ""
  match responses_result {
    { "output": Array(output), .. } =>
      for item in output {
        match item {
          { "type": String("function_call"), "call_id": String(cid), .. } =>
            responses_call_id = cid
          _ => ()
        }
      }
    _ => ()
  }
  // Verify ID suffix is preserved
  assert_true(is_same_tool_call_id(original_claude_id, responses_call_id))
  // Now simulate sending tool result back
  let tool_result_request : Json = {
    "model": "claude-sonnet-4-20250514",
    "input": Json::array([
      { "role": "user", "content": "What's the weather?" },
      {
        "type": "function_call",
        "call_id": responses_call_id,
        "name": "get_weather",
        "arguments": "{}",
      },
      {
        "type": "function_call_output",
        "call_id": responses_call_id,
        "output": "Sunny",
      },
    ]),
  }
  // Convert to Anthropic
  let anthropic_req = responses_request_to_anthropic(tool_result_request)
  // The tool_result should use the original Anthropic format ID
  match anthropic_req {
    { "messages": Array(msgs), .. } =>
      // Find the tool result message
      for msg in msgs {
        match msg {
          { "content": Array(content), .. } =>
            for c in content {
              match c {
                { "type": String("tool_result"), "tool_use_id": String(id), .. } =>
                  // The ID should be traceable back to original
                  assert_true(
                    is_same_tool_call_id(original_claude_id, id) ||
                    is_same_tool_call_id(responses_call_id, id),
                  )
                _ => ()
              }
            }
          _ => ()
        }
      }
    _ => ()
  }
}
