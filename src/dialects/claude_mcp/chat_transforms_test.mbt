///|
/// Public response-side tests for `claude mcp serve`

///|
test "tools_result_to_chat: single text content" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"file contents here"}]}}
  let result = tools_result_to_chat(body)
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
test "tools_result_to_chat: has usage" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"ok"}]}}
  let result = tools_result_to_chat(body)
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
test "tools_result_to_chat: has id and model" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"ok"}]}}
  let result = tools_result_to_chat(body)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "id": String(_), "model": String(_), .. } => ()
    _ => fail("Missing id or model")
  }
}

///|
test "tools_result_to_chat: isError true" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"Permission denied"}],"isError":true}}
  let result = tools_result_to_chat(body)
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
test "tools_result_to_chat: plain text fallback" {
  let result = tools_result_to_chat("raw text response")
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(c), .. }, .. } =>
          assert_eq(c, "raw text response")
        _ => fail("Invalid choice")
      }
    _ => fail("Invalid format")
  }
}

///|
test "tools_result_to_chat: non-tool result falls back to wrapped text" {
  let non_tool_result =
    #|{"jsonrpc":"2.0","method":"notifications/initialized"}
  let response_json = @json.parse(tools_result_to_chat(non_tool_result)) catch {
    _ => fail("Failed to parse simple chat response")
  }
  match response_json {
    {
      "choices": Array([{ "message": { "content": String(content), .. }, .. }]),
      ..
    } => assert_eq(content, non_tool_result)
    _ => fail("Expected simple chat fallback response")
  }
}

///|
test "tools_result_to_chat: Read fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_read_response.json",
  )
  let result = tools_result_to_chat(fixture)
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
test "tools_result_to_chat: error fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_error_response.json",
  )
  let result = tools_result_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "message": String(m), .. }, .. } =>
      assert_true(m.contains("ENOENT"))
    _ => fail("Expected error response from fixture")
  }
}

///|
test "tools_result_to_chat: Bash fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_bash_response.json",
  )
  let result = tools_result_to_chat(fixture)
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
test "tools_result_to_chat: multi content fixture" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_multi_content.json",
  )
  let result = tools_result_to_chat(fixture)
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
test "tools_result_to_chat: initialize response not a tool result" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/initialize_response.json",
  )
  let result = tools_result_to_chat(fixture)
  let json = @json.parse(result) catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(_), .. } => ()
    _ => fail("Should produce a chat completion even for non-tool results")
  }
}
