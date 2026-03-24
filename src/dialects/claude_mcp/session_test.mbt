///|
/// Public request-side/session tests for `claude mcp serve`

///|
fn extract_bash_command(req : ClaudeMcpUpstreamRequest) -> String raise {
  let call_json = @json.parse(req.steps[req.steps.length() - 1].message) catch {
    _ => fail("invalid tools/call request")
  }
  match call_json {
    {
      "method": String("tools/call"),
      "params": {
        "name": String("Bash"),
        "arguments": { "command": String(command), .. },
        ..
      },
      ..
    } => command
    _ => fail("unexpected tools/call shape")
  }
}

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
    @mcp.McpToolDefinition::{
      name: "Read",
      description: "Read",
      input_schema: {},
    },
    @mcp.McpToolDefinition::{
      name: "Bash",
      description: "Run",
      input_schema: {},
    },
  ]
  let updated = update_session_tools(session, tools)
  assert_eq(updated.tools.length(), 2)
  assert_eq(updated.tools[0].name, "Read")
  assert_eq(updated.tools[1].name, "Bash")
  assert_eq(updated.phase, Uninitialized)
}

///|
test "prepare_initialize: produces 2 steps" {
  let session = ClaudeMcpSession::new()
  let req = prepare_initialize(session)
  assert_eq(req.steps.length(), 2)
  assert_eq(req.steps[0].kind, @jsonrpc.Request)
  assert_eq(req.steps[1].kind, @jsonrpc.Notification)
  assert_eq(req.next_session.phase, Ready)
  assert_eq(req.next_session.next_id, 2)
}

///|
test "prepare_initialize: first step is valid initialize request" {
  let session = ClaudeMcpSession::new()
  let req = prepare_initialize(session)
  let json = @json.parse(req.steps[0].message) catch {
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
  let json = @json.parse(req.steps[1].message) catch {
    _ => fail("Failed to parse notification")
  }
  match json {
    { "method": String("notifications/initialized"), .. } => ()
    _ => fail("Invalid notification")
  }
}

///|
test "prepare_tools_list: from uninitialized includes init" {
  let session = ClaudeMcpSession::new()
  let req = prepare_tools_list(session)
  assert_eq(req.steps.length(), 3)
  assert_eq(req.steps[0].kind, @jsonrpc.Request)
  assert_eq(req.steps[1].kind, @jsonrpc.Notification)
  assert_eq(req.steps[2].kind, @jsonrpc.Request)
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
  let json = @json.parse(req.steps[0].message) catch {
    _ => fail("Failed to parse")
  }
  match json {
    { "method": String("tools/list"), "id": Number(id, ..), .. } =>
      assert_eq(id.to_int(), 3)
    _ => fail("Not a tools/list request")
  }
}

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
  let json = @json.parse(req.steps[0].message) catch {
    _ => fail("Failed to parse")
  }
  match json {
    {
      "method": String("tools/call"),
      "id": Number(id, ..),
      "params": { "name": String(n), .. },
      ..
    } => {
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

///|
test "prepare_chat_upstream: extracts prompt and uses Bash tool" {
  let session = ClaudeMcpSession::new()
  let body =
    #|{"model":"gpt-4o","messages":[{"role":"system","content":"Be concise"},{"role":"user","content":"ls -la"}]}
  let req = prepare_chat_upstream(
    session,
    body,
    @types.TransformContext::default(),
  )
  assert_eq(req.steps.length(), 3)
  let command = extract_bash_command(req)
  assert_true(command.contains("Be concise"))
  assert_true(command.contains("ls -la"))
}

///|
test "prepare_chat_upstream: uses last user message" {
  let session = ClaudeMcpSession::new()
  let body =
    #|{"model":"gpt-4o","messages":[{"role":"user","content":"first"},{"role":"assistant","content":"reply"},{"role":"user","content":"second"}]}
  let req = prepare_chat_upstream(
    session,
    body,
    @types.TransformContext::default(),
  )
  assert_eq(extract_bash_command(req), "second")
}

///|
test "prepare_chat_upstream: multipart user content keeps text parts" {
  let session = ClaudeMcpSession::new()
  let body =
    #|{"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"https://example.com/a.png"}},{"type":"text","text":"part1"},{"type":"text","text":"part2"}]}]}
  let req = prepare_chat_upstream(
    session,
    body,
    @types.TransformContext::default(),
  )
  assert_eq(extract_bash_command(req), "part1\npart2")
}

///|
test "prepare_chat_upstream: system only prompt is preserved" {
  let session = ClaudeMcpSession::new()
  let body =
    #|{"messages":[{"role":"system","content":"System prompt only"}]}
  let req = prepare_chat_upstream(
    session,
    body,
    @types.TransformContext::default(),
  )
  assert_eq(extract_bash_command(req), "System prompt only")
}

///|
test "prepare_chat_upstream: invalid JSON falls back to raw body" {
  let session = ClaudeMcpSession::new()
  let req = prepare_chat_upstream(
    session,
    "not json",
    @types.TransformContext::default(),
  )
  assert_eq(extract_bash_command(req), "not json")
}

///|
test "prepare_chat_upstream: missing messages falls back to raw body" {
  let session = ClaudeMcpSession::new()
  let body =
    #|{"model":"m"}
  let req = prepare_chat_upstream(
    session,
    body,
    @types.TransformContext::default(),
  )
  assert_eq(extract_bash_command(req), body)
}

///|
test "ClaudeMcpConfig::default" {
  let cfg = ClaudeMcpConfig::default()
  assert_eq(cfg.command, "claude")
  assert_eq(cfg.args, ["mcp", "serve"])
  assert_eq(cfg.timeout_ms, 30000)
  assert_eq(cfg.env.length(), 0)
}
