///|
/// Fixture-based interoperability tests
/// Tests with real API response fixtures from llm-interop TypeScript

// =============================================================================
// Fixture Loading Utilities
// =============================================================================

///|
/// Read a JSONL file and return lines as array
fn read_jsonl_lines(path : String) -> Array[String] raise {
  let content = @fs.read_file_to_string(path)
  @utils.split_lines(content)
}

///|
/// Get a specific line from a JSONL file (0-indexed)
fn get_jsonl_line(path : String, index : Int) -> String raise {
  let lines = read_jsonl_lines(path)
  if index >= 0 && index < lines.length() {
    lines[index]
  } else {
    raise @builtin.Failure("Line index out of bounds: \{index}")
  }
}

// =============================================================================
// Claude Message Fixtures (from fixtures/claude/message-sync.jsonl)
// =============================================================================

///|
/// Claude text response fixture (line 0)
fn claude_text_response_fixture() -> String raise {
  get_jsonl_line("fixtures/claude/message-sync.jsonl", 0)
}

///|
/// Claude tool_use response fixture (line 7)
fn claude_tool_use_fixture() -> String raise {
  get_jsonl_line("fixtures/claude/message-sync.jsonl", 7)
}

///|
/// Claude multi-tool response fixture (line 8)
fn claude_multi_tool_fixture() -> String raise {
  get_jsonl_line("fixtures/claude/message-sync.jsonl", 8)
}

///|
/// Claude tool result continuation fixture (line 9)
fn claude_tool_result_continuation_fixture() -> String raise {
  get_jsonl_line("fixtures/claude/message-sync.jsonl", 9)
}

// =============================================================================
// Test: Parse Claude Fixtures and Convert to Responses API
// =============================================================================

///|
test "fixture: parse Claude text response" {
  let fixture = claude_text_response_fixture()
  let json = @json.parse(fixture) catch {
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
  let fixture = claude_tool_use_fixture()
  let json = @json.parse(fixture) catch {
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
  let fixture = claude_multi_tool_fixture()
  let json = @json.parse(fixture) catch {
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
  let fixture = claude_tool_use_fixture()
  let anthropic_response = @json.parse(fixture) catch {
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
  let final_fixture = claude_tool_result_continuation_fixture()
  let final_response = @json.parse(final_fixture) catch {
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
  // Claude responds with tool_use
  let fixture = claude_tool_use_fixture()
  let anthropic_response = @json.parse(fixture) catch {
    _ => {
      fail("Failed to parse")
      return
    }
  }
  // Extract the original Claude ID from the fixture
  let original_claude_id = match anthropic_response {
    { "content": Array(content), .. } => {
      let mut id = ""
      for c in content {
        match c {
          { "type": String("tool_use"), "id": String(tid), .. } => id = tid
          _ => ()
        }
      }
      id
    }
    _ => ""
  }
  assert_true(original_claude_id.has_prefix("toolu_"))
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
