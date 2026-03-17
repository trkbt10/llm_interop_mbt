///|
/// Exhaustive tests for `claude mcp serve` dialect

// =============================================================================
// Session state
// =============================================================================

///|
test "ClaudeMcpSession::new" {
  let session = ClaudeMcpSession::new()
  assert_eq(session.phase, Uninitialized)
  assert_eq(session.next_id, 1)
  assert_eq(session.tools.length(), 0)
}

///|
test "update_session_tools" {
  let session = ClaudeMcpSession::new()
  let tools = [
    @mcp.McpToolDefinition::{ name: "Read", description: "Read", input_schema: {} },
    @mcp.McpToolDefinition::{ name: "Bash", description: "Run", input_schema: {} },
  ]
  let updated = update_session_tools(session, tools)
  assert_eq(updated.tools.length(), 2)
  assert_eq(updated.tools[0].name, "Read")
  assert_eq(updated.tools[1].name, "Bash")
  // Phase unchanged
  assert_eq(updated.phase, Uninitialized)
}

// =============================================================================
// prepare_initialize
// =============================================================================

///|
test "prepare_initialize: produces 2 steps" {
  let session = ClaudeMcpSession::new()
  let req = prepare_initialize(session)
  assert_eq(req.steps.length(), 2)
  assert_eq(req.steps[0].kind, @jsonrpc.Request)
  assert_eq(req.steps[1].kind, @jsonrpc.Notification)
  assert_eq(req.next_session.phase, Ready)
  assert_eq(req.next_session.next_id, 2) // id 1 used for initialize
}

///|
test "prepare_initialize: first step is valid initialize request" {
  let session = ClaudeMcpSession::new()
  let req = prepare_initialize(session)
  let json = try { @json.parse(req.steps[0].message) } catch {
    _ => fail("Failed to parse initialize request")
  }
  match json {
    { "jsonrpc": String("2.0"), "method": String("initialize"), .. } => ()
    _ => fail("Invalid initialize request")
  }
}

///|
test "prepare_initialize: second step is initialized notification" {
  let session = ClaudeMcpSession::new()
  let req = prepare_initialize(session)
  let json = try { @json.parse(req.steps[1].message) } catch {
    _ => fail("Failed to parse notification")
  }
  match json {
    { "method": String("notifications/initialized"), .. } => ()
    _ => fail("Invalid notification")
  }
}

// =============================================================================
// prepare_tools_list
// =============================================================================

///|
test "prepare_tools_list: from uninitialized includes init" {
  let session = ClaudeMcpSession::new()
  let req = prepare_tools_list(session)
  assert_eq(req.steps.length(), 3)
  assert_eq(req.steps[0].kind, @jsonrpc.Request) // initialize
  assert_eq(req.steps[1].kind, @jsonrpc.Notification) // initialized
  assert_eq(req.steps[2].kind, @jsonrpc.Request) // tools/list
  assert_eq(req.next_session.phase, Ready)
}

///|
test "prepare_tools_list: from ready is single step" {
  let session : ClaudeMcpSession = { phase: Ready, next_id: 5, tools: [] }
  let req = prepare_tools_list(session)
  assert_eq(req.steps.length(), 1)
  assert_eq(req.steps[0].kind, @jsonrpc.Request)
  assert_eq(req.next_session.next_id, 6)
}

///|
test "prepare_tools_list: from ready sends tools/list" {
  let session : ClaudeMcpSession = { phase: Ready, next_id: 3, tools: [] }
  let req = prepare_tools_list(session)
  let json = try { @json.parse(req.steps[0].message) } catch {
    _ => fail("Failed to parse")
  }
  match json {
    { "method": String("tools/list"), "id": Number(id, ..), .. } =>
      assert_eq(id.to_int(), 3)
    _ => fail("Not a tools/list request")
  }
}

// =============================================================================
// prepare_tools_call
// =============================================================================

///|
test "prepare_tools_call: from uninitialized includes init" {
  let session = ClaudeMcpSession::new()
  let args : Json = { "command": "ls" }
  let req = prepare_tools_call(session, "Bash", args)
  assert_eq(req.steps.length(), 3)
  assert_eq(req.next_session.phase, Ready)
}

///|
test "prepare_tools_call: from ready is single step" {
  let session : ClaudeMcpSession = { phase: Ready, next_id: 3, tools: [] }
  let args : Json = { "file_path": "/tmp/test" }
  let req = prepare_tools_call(session, "Read", args)
  assert_eq(req.steps.length(), 1)
  assert_eq(req.next_session.next_id, 4)
}

///|
test "prepare_tools_call: sends correct tool and arguments" {
  let session : ClaudeMcpSession = { phase: Ready, next_id: 7, tools: [] }
  let args : Json = { "file_path": "/tmp/hello.txt", "offset": 10 }
  let req = prepare_tools_call(session, "Read", args)
  let json = try { @json.parse(req.steps[0].message) } catch {
    _ => fail("Failed to parse")
  }
  match json {
    { "method": String("tools/call"), "id": Number(id, ..), "params": { "name": String(n), .. }, .. } => {
      assert_eq(id.to_int(), 7)
      assert_eq(n, "Read")
    }
    _ => fail("Invalid tools/call request")
  }
}

///|
test "prepare_tools_call: id increments correctly across calls" {
  let session : ClaudeMcpSession = { phase: Ready, next_id: 10, tools: [] }
  let req1 = prepare_tools_call(session, "Read", {})
  assert_eq(req1.next_session.next_id, 11)
  let req2 = prepare_tools_call(req1.next_session, "Write", {})
  assert_eq(req2.next_session.next_id, 12)
}

// =============================================================================
// chat_request_to_prompt
// =============================================================================

///|
test "chat_request_to_prompt: basic user message" {
  let body =
    #|{"model":"claude-code-tools","messages":[{"role":"user","content":"Read /tmp/test.txt"}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "prompt": String(p), "model": String(m), .. } => {
      assert_eq(p, "Read /tmp/test.txt")
      assert_eq(m, "claude-code-tools")
    }
    _ => fail("Invalid format")
  }
}

///|
test "chat_request_to_prompt: system + user concatenated" {
  let body =
    #|{"model":"m","messages":[{"role":"system","content":"You are helpful"},{"role":"user","content":"Hello"}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "prompt": String(p), .. } =>
      assert_eq(p, "You are helpful\n\nHello")
    _ => fail("Invalid format")
  }
}

///|
test "chat_request_to_prompt: picks last user message" {
  let body =
    #|{"model":"m","messages":[{"role":"user","content":"first"},{"role":"assistant","content":"reply"},{"role":"user","content":"second"}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "prompt": String(p), .. } => assert_eq(p, "second")
    _ => fail("Invalid format")
  }
}

///|
test "chat_request_to_prompt: multipart content" {
  let body =
    #|{"model":"m","messages":[{"role":"user","content":[{"type":"text","text":"part1"},{"type":"text","text":"part2"}]}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "prompt": String(p), .. } => assert_eq(p, "part1\npart2")
    _ => fail("Invalid format")
  }
}

///|
test "chat_request_to_prompt: system only" {
  let body =
    #|{"model":"m","messages":[{"role":"system","content":"System prompt only"}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "prompt": String(p), .. } => assert_eq(p, "System prompt only")
    _ => fail("Invalid format")
  }
}

///|
test "chat_request_to_prompt: preserves messages array" {
  let body =
    #|{"model":"m","messages":[{"role":"user","content":"hi"}]}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "messages": Array(msgs), .. } => assert_eq(msgs.length(), 1)
    _ => fail("messages array not preserved")
  }
}

///|
test "chat_request_to_prompt: invalid JSON returns input" {
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt("not json", ctx)
  assert_eq(result, "not json")
}

///|
test "chat_request_to_prompt: no messages returns input" {
  let body =
    #|{"model":"m"}
  let ctx = @types.TransformContext::default()
  let result = chat_request_to_prompt(body, ctx)
  assert_eq(result, body)
}

// =============================================================================
// tools_result_to_chat: success cases
// =============================================================================

///|
test "tools_result_to_chat: single text content" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"file contents here"}]}}
  let result = tools_result_to_chat(body)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "object": String("chat.completion"), "choices": Array(choices), .. } => {
      assert_eq(choices.length(), 1)
      match choices[0] {
        { "message": { "content": String(c), "role": String("assistant"), .. }, "finish_reason": String("stop"), .. } =>
          assert_eq(c, "file contents here")
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
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "usage": { "prompt_tokens": Number(_), "completion_tokens": Number(_), "total_tokens": Number(_), .. }, .. } =>
      ()
    _ => fail("Missing usage in response")
  }
}

///|
test "tools_result_to_chat: has id and model" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"ok"}]}}
  let result = tools_result_to_chat(body)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "id": String(_), "model": String(_), .. } => ()
    _ => fail("Missing id or model")
  }
}

// =============================================================================
// tools_result_to_chat: error cases
// =============================================================================

///|
test "tools_result_to_chat: isError true" {
  let body =
    #|{"result":{"content":[{"type":"text","text":"Permission denied"}],"isError":true}}
  let result = tools_result_to_chat(body)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
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
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
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

// =============================================================================
// tools_result_to_chat: fixture-based tests
// =============================================================================

///|
test "tools_result_to_chat: Read fixture" {
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_read_response.json")
  let result = tools_result_to_chat(fixture)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
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
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_error_response.json")
  let result = tools_result_to_chat(fixture)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "message": String(m), .. }, .. } =>
      assert_true(m.contains("ENOENT"))
    _ => fail("Expected error response from fixture")
  }
}

///|
test "tools_result_to_chat: Bash fixture" {
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_bash_response.json")
  let result = tools_result_to_chat(fixture)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
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
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_multi_content.json")
  let result = tools_result_to_chat(fixture)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
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
  let fixture = @utils.read_testdata("testdata/claude_mcp/initialize_response.json")
  // initialize response has result.protocolVersion, not result.content
  // Should fall through to plain text wrapping
  let result = tools_result_to_chat(fixture)
  let json = try { @json.parse(result) } catch { _ => fail("Failed to parse") }
  match json {
    { "choices": Array(_), .. } => () // Wrapped as plain text
    _ => fail("Should produce a chat completion even for non-tool results")
  }
}

// =============================================================================
// Config
// =============================================================================

///|
test "ClaudeMcpConfig::default" {
  let cfg = ClaudeMcpConfig::default()
  assert_eq(cfg.command, "claude")
  assert_eq(cfg.args, ["mcp", "serve"])
  assert_eq(cfg.timeout_ms, 30000)
  assert_eq(cfg.env.size(), 0)
}
