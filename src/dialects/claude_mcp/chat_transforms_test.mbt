///|
/// Public response-side tests for `claude mcp serve`

///|
test "response_to_chat: single text content" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"file contents here"}]}}
  let result = response_to_chat(body)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "object": String("chat.completion"), "choices": Array(choices), .. } => {
      assert_eq(choices.length(), 1)
      match choices[0] {
        {
          "message": { "content": String(c), "role": String("assistant"), .. },
          "finish_reason": String("stop"),
          ..
        } => assert_eq(c, "file contents here")
        _ => fail("Invalid choice")
      }
    }
    _ => fail("Invalid chat completion format")
  }
}

///|
test "response_to_chat: has usage" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"ok"}]}}
  let result = response_to_chat(body)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    {
      "usage": {
        "prompt_tokens": Number(_),
        "completion_tokens": Number(_),
        "total_tokens": Number(_),
        ..
      },
      ..
    } => ()
    _ => fail("Missing usage in response")
  }
}

///|
test "response_to_chat: has id and model" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"ok"}]}}
  let result = response_to_chat(body)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "id": String(_), "model": String(_), .. } => ()
    _ => fail("Missing id or model")
  }
}

///|
test "response_to_chat: isError true" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"Permission denied"}],"isError":true}}
  let result = response_to_chat(body)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "message": String(m), "type": String(t), .. }, .. } => {
      assert_eq(m, "Permission denied")
      assert_eq(t, "claude_mcp_error")
    }
    _ => fail("Expected error response")
  }
}

///|
test "response_to_chat: invalid JSON becomes structured failure" {
  let result = response_to_chat("raw text response")
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "parse_error")
      assert_true(
        message.contains(
          "`claude mcp serve` tools result bridge requires valid JSON",
        ),
      )
    }
    _ => fail("Expected structured parse failure")
  }
}

///|
test "response_to_chat: non-tool result becomes structured failure" {
  let non_tool_result =
    #|{"jsonrpc":"2.0","method":"notifications/initialized"}
  let response_json = @json.parse(response_to_chat(non_tool_result)) catch {
    _ => fail("Failed to parse error response")
  }
  match response_json {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "parse_error")
      assert_true(message.contains("tools/call result payload"))
    }
    _ => fail("Expected parse failure for non-tool result")
  }
}

///|
test "response_to_chat: Read fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_read_response.json",
  )
  let result = response_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(c), .. }, .. } =>
          assert_true(c.contains("Hello, world!"))
        _ => fail("Invalid choice")
      }
    _ => fail("Invalid format")
  }
}

///|
test "response_to_chat: error fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_error_response.json",
  )
  let result = response_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "message": String(m), .. }, .. } =>
      assert_true(m.contains("ENOENT"))
    _ => fail("Expected error response from fixture")
  }
}

///|
test "response_to_chat: Bash fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_bash_response.json",
  )
  let result = response_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(c), .. }, .. } => {
          assert_true(c.contains("README.md"))
          assert_true(c.contains("moon.pkg.json"))
        }
        _ => fail("Invalid choice")
      }
    _ => fail("Invalid format")
  }
}

///|
test "response_to_chat: multi content fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_multi_content.json",
  )
  let result = response_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(c), .. }, .. } => {
          assert_true(c.contains("File 1 contents"))
          assert_true(c.contains("File 2 contents"))
          assert_true(c.contains("File 3 contents"))
        }
        _ => fail("Invalid choice")
      }
    _ => fail("Invalid format")
  }
}

///|
test "response_to_chat: initialize response not a tool result" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/initialize_response.json",
  )
  let result = response_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "type": String(type_), .. }, .. } =>
      assert_eq(type_, "parse_error")
    _ => fail("Should reject non-tools/call payloads")
  }
}

///|
test "parse_response: successful tools result becomes text response" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"file contents here"}]}}
  match parse_response(body) {
    @types.ModelResponse::Text(text) => assert_eq(text, "file contents here")
    _ => fail("Expected text response")
  }
}

///|
test "parse_response: tool error becomes structured failure" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"Permission denied"}],"isError":true}}
  match parse_response(body).as_failure() {
    Some(failure) => {
      assert_eq(failure.type_, "claude_mcp_error")
      assert_eq(failure.message, "Permission denied")
    }
    None => fail("Expected failure")
  }
}

///|
test "response_to_responses: successful tools result becomes message output" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"file contents here"}]}}
  match
    response_to_responses(
      body,
      response_id="resp_claude_mcp",
      model="claude-code-tools",
    ) {
    {
      "id": String("resp_claude_mcp"),
      "output": [
        {
          "type": String("message"),
          "role": String("assistant"),
          "content": [
            { "type": String("output_text"), "text": String(text), .. },
            ..,
          ],
          ..
        },
        ..,
      ],
      ..
    } => assert_eq(text, "file contents here")
    other => fail("Unexpected Responses JSON: " + other.stringify())
  }
}

///|
test "response_to_responses: invalid payload becomes Responses error" {
  match
    response_to_responses(
      "raw text response",
      response_id="resp_claude_mcp_bad",
      model="claude-code-tools",
    ) {
    { "error": { "type": String(type_), .. }, .. } =>
      assert_eq(type_, "parse_error")
    _ => fail("Expected Responses error payload")
  }
}
