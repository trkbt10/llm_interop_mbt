///|
/// Tests for MCP server-side responses and request parsing

// =============================================================================
// build_initialize_result
// =============================================================================

///|
test "build_initialize_result: valid JSON-RPC response" {
  let result = build_initialize_result(1)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "result": {
        "protocolVersion": String("2025-03-26"),
        "serverInfo": {
          "name": String("llm_interop-mcp-server"),
          "version": String("0.1.0"),
          ..
        },
        "capabilities": { "tools": _, .. },
        ..
      },
      ..
    } => assert_eq(id.to_int(), 1)
    _ => fail("unexpected structure: " + result)
  }
}

///|
test "build_initialize_result: different id" {
  let result = build_initialize_result(42)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "id": Number(id, ..), .. } => assert_eq(id.to_int(), 42)
    _ => fail("missing id")
  }
}

///|
test "build_initialize_result: matches fixture structure" {
  // Verify our server response has the same structure as the real
  // `claude mcp serve` initialize response in fixtures
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/initialize_response.json",
  )
  let fixture_json = @json.parse(fixture) catch { _ => fail("invalid fixture") }
  let our_result = build_initialize_result(1)
  let our_json = @json.parse(our_result) catch { _ => fail("invalid json") }
  // Both must have: jsonrpc, id, result.protocolVersion, result.capabilities.tools, result.serverInfo
  match fixture_json {
    {
      "jsonrpc": String("2.0"),
      "result": {
        "protocolVersion": String(_),
        "capabilities": { "tools": _, .. },
        "serverInfo": { "name": String(_), "version": String(_), .. },
        ..
      },
      ..
    } => ()
    _ => fail("fixture has unexpected structure")
  }
  match our_json {
    {
      "jsonrpc": String("2.0"),
      "result": {
        "protocolVersion": String(_),
        "capabilities": { "tools": _, .. },
        "serverInfo": { "name": String(_), "version": String(_), .. },
        ..
      },
      ..
    } => ()
    _ => fail("our response has unexpected structure")
  }
}

// =============================================================================
// build_tools_list_result
// =============================================================================

///|
test "build_tools_list_result: empty tools" {
  let result = build_tools_list_result(1, [])
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "result": { "tools": Array(tools), .. }, .. } =>
      assert_eq(tools.length(), 0)
    _ => fail("unexpected structure")
  }
}

///|
test "build_tools_list_result: multiple tools" {
  let tools = [
    @mcp.McpToolDefinition::{
      name: "gpt-4o",
      description: "GPT-4o (openai)",
      input_schema: {},
    },
    @mcp.McpToolDefinition::{
      name: "claude-sonnet-4-20250514",
      description: "Claude Sonnet (anthropic)",
      input_schema: {},
    },
  ]
  let result = build_tools_list_result(2, tools)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "id": Number(id, ..), "result": { "tools": Array(arr), .. }, .. } => {
      assert_eq(id.to_int(), 2)
      assert_eq(arr.length(), 2)
      match arr[0] {
        { "name": String(n), "description": String(d), .. } => {
          assert_eq(n, "gpt-4o")
          assert_eq(d, "GPT-4o (openai)")
        }
        _ => fail("invalid tool[0]")
      }
      match arr[1] {
        { "name": String(n), .. } => assert_eq(n, "claude-sonnet-4-20250514")
        _ => fail("invalid tool[1]")
      }
    }
    _ => fail("unexpected structure")
  }
}

///|
test "build_tools_list_result: roundtrip with parse_tools_list_response" {
  let tools = [
    @mcp.McpToolDefinition::{
      name: "gpt-4o",
      description: "GPT-4o",
      input_schema: { "type": "object" },
    },
  ]
  let response = build_tools_list_result(1, tools)
  let json = @json.parse(response) catch { _ => fail("invalid json") }
  let parsed = @mcp.parse_tools_list_response(json)
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].name, "gpt-4o")
  assert_eq(parsed[0].description, "GPT-4o")
}

///|
test "build_tools_list_result: matches fixture structure" {
  // Verify each tool has same shape as real `claude mcp serve` tools/list
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_list_response.json",
  )
  let fixture_json = @json.parse(fixture) catch { _ => fail("invalid fixture") }
  // Parse fixture tools
  let fixture_tools = @mcp.parse_tools_list_response(fixture_json)
  assert_true(fixture_tools.length() > 0)
  // Each fixture tool has name, description, inputSchema with type/properties/required
  for ft in fixture_tools {
    assert_true(ft.name.length() > 0)
    match ft.input_schema {
      { "type": String("object"), "properties": _, "required": Array(_), .. } =>
        ()
      _ => fail("fixture tool " + ft.name + " has unexpected schema")
    }
  }
  // Build our tools and verify same structure
  let our_tools = [model_to_mcp_tool("gpt-4o", "GPT-4o", "openai")]
  let our_response = build_tools_list_result(2, our_tools)
  let our_json = @json.parse(our_response) catch { _ => fail("invalid json") }
  let our_parsed = @mcp.parse_tools_list_response(our_json)
  assert_eq(our_parsed.length(), 1)
  // Our tools must also have name, description, inputSchema with type/properties/required
  match our_parsed[0].input_schema {
    { "type": String("object"), "properties": _, "required": Array(_), .. } =>
      ()
    _ => fail("our tool has unexpected schema")
  }
}

// =============================================================================
// build_tools_call_result
// =============================================================================

///|
test "build_tools_call_result: success" {
  let result = build_tools_call_result(3, "Hello!", false)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "id": Number(id, ..), "result": { "content": Array(items), .. }, .. } => {
      assert_eq(id.to_int(), 3)
      assert_eq(items.length(), 1)
      match items[0] {
        { "type": String("text"), "text": String("Hello!"), .. } => ()
        _ => fail("invalid content item")
      }
    }
    _ => fail("unexpected structure: " + result)
  }
  // No isError field when not error
  match json {
    { "result": { "isError": _, .. }, .. } => fail("should not have isError")
    _ => ()
  }
}

///|
test "build_tools_call_result: error" {
  let result = build_tools_call_result(4, "Something went wrong", true)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "result": { "isError": True, "content": Array(items), .. }, .. } =>
      match items[0] {
        { "text": String(t), .. } => assert_eq(t, "Something went wrong")
        _ => fail("invalid content")
      }
    _ => fail("expected isError: true")
  }
}

///|
test "build_tools_call_result: roundtrip with parse_tools_call_result" {
  let response = build_tools_call_result(1, "test content", false)
  let json = @json.parse(response) catch { _ => fail("invalid json") }
  let parsed = @mcp.parse_tools_call_result(json)
  match parsed {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_eq(r.content.length(), 1)
      match r.content[0] {
        @mcp.McpContentItem::Text(text) => assert_eq(text, "test content")
        _ => fail("Expected Text")
      }
    }
    None => fail("parse failed")
  }
}

///|
test "build_tools_call_result: matches fixture success structure" {
  // Compare with real `claude mcp serve` tools/call response fixture
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_read_response.json",
  )
  let fixture_json = @json.parse(fixture) catch { _ => fail("invalid fixture") }
  let fixture_result = @mcp.parse_tools_call_result(fixture_json)
  match fixture_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_true(r.content.length() > 0)
      match r.content[0] {
        @mcp.McpContentItem::Text(_) => ()
        _ => fail("Expected Text content")
      }
    }
    None => fail("failed to parse fixture")
  }
  // Our response should parse identically
  let our_response = build_tools_call_result(
    3, "Hello, world!\nThis is a test file.", false,
  )
  let our_json = @json.parse(our_response) catch { _ => fail("invalid json") }
  let our_result = @mcp.parse_tools_call_result(our_json)
  match our_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_eq(r.content.length(), 1)
      match r.content[0] {
        @mcp.McpContentItem::Text(text) =>
          assert_eq(text, "Hello, world!\nThis is a test file.")
        _ => fail("Expected Text content")
      }
    }
    None => fail("failed to parse our response")
  }
}

///|
test "build_tools_call_result: matches fixture error structure" {
  let fixture = @utils.read_testdata(
    "testdata/claude_mcp/tools_call_error_response.json",
  )
  let fixture_json = @json.parse(fixture) catch { _ => fail("invalid fixture") }
  let fixture_result = @mcp.parse_tools_call_result(fixture_json)
  match fixture_result {
    Some(r) => {
      assert_eq(r.is_error, true)
      match r.content[0] {
        @mcp.McpContentItem::Text(text) => assert_true(text.contains("ENOENT"))
        _ => fail("Expected Text")
      }
    }
    None => fail("failed to parse fixture")
  }
  // Our error response should parse the same way
  let our_response = build_tools_call_result(
    4, "Error: ENOENT: file not found", true,
  )
  let our_json = @json.parse(our_response) catch { _ => fail("invalid json") }
  let our_result = @mcp.parse_tools_call_result(our_json)
  match our_result {
    Some(r) => {
      assert_eq(r.is_error, true)
      match r.content[0] {
        @mcp.McpContentItem::Text(text) => assert_true(text.contains("ENOENT"))
        _ => fail("Expected Text")
      }
    }
    None => fail("failed to parse our error response")
  }
}

// =============================================================================
// build_ping_result
// =============================================================================

///|
test "build_ping_result" {
  let result = build_ping_result(5)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "result": Object(obj),
      ..
    } => {
      assert_eq(id.to_int(), 5)
      assert_eq(obj.length(), 0)
    }
    _ => fail("unexpected structure")
  }
}

// =============================================================================
// Canonical server-side bridges
// =============================================================================

///|
test "tools_call_params_to_chat_request: valid params" {
  let params : Json = {
    "name": "gpt-4o",
    "arguments": {
      "prompt": "Say hello",
      "system": "You are helpful",
      "max_tokens": 1024,
    },
  }
  match tools_call_params_to_chat_request(Some(params)) {
    Some(request) => {
      assert_eq(request.model, "gpt-4o")
      let json = @json.parse(request.body) catch { _ => fail("invalid json") }
      match json {
        {
          "model": String("gpt-4o"),
          "messages": Array(msgs),
          "max_tokens": Number(mt, ..),
          "stream": False,
          ..
        } => {
          assert_eq(msgs.length(), 2)
          assert_eq(mt.to_int(), 1024)
        }
        _ => fail("unexpected request shape")
      }
    }
    None => fail("expected Some")
  }
}

///|
test "tools_call_params_to_chat_request: defaults optional args" {
  let params : Json = { "name": "gpt-4o", "arguments": { "prompt": "Hello" } }
  match tools_call_params_to_chat_request(Some(params)) {
    Some(request) => {
      let json = @json.parse(request.body) catch { _ => fail("invalid json") }
      match json {
        {
          "messages": [
            { "role": String("user"), "content": String("Hello"), .. },
          ],
          "max_tokens": Number(mt, ..),
          ..
        } => assert_eq(mt.to_int(), 4096)
        _ => fail("unexpected request shape")
      }
    }
    None => fail("expected Some")
  }
}

///|
test "tools_call_params_to_chat_request: rejects missing name" {
  let params : Json = { "arguments": { "prompt": "Hello" } }
  assert_eq(tools_call_params_to_chat_request(Some(params)), None)
}

// =============================================================================
// model_to_mcp_tool
// =============================================================================

///|
test "model_to_mcp_tool: creates tool definition" {
  let tool = model_to_mcp_tool("gpt-4o", "GPT-4o", "openai")
  assert_eq(tool.name, "gpt-4o")
  assert_eq(tool.description, "GPT-4o (openai)")
  // Verify input schema has required prompt field
  match tool.input_schema {
    {
      "type": String("object"),
      "properties": { "prompt": _, "system": _, "max_tokens": _, .. },
      "required": Array(req),
      ..
    } => {
      assert_eq(req.length(), 1)
      match req[0] {
        String("prompt") => ()
        _ => fail("expected 'prompt' in required")
      }
    }
    _ => fail("invalid input schema")
  }
}

///|
test "chat_response_to_tools_call_result: success" {
  let body =
    #|{"choices":[{"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
  let result = chat_response_to_tools_call_result(7, body)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match @mcp.parse_tools_call_result(json) {
    Some(parsed) => {
      assert_eq(parsed.is_error, false)
      assert_eq(@mcp.extract_text_content(parsed), "Hello!")
    }
    None => fail("parse failed")
  }
}

///|
test "chat_response_to_tools_call_result: openai error becomes MCP error" {
  let body =
    #|{"error":{"message":"boom","type":"api_error"}}
  let result = chat_response_to_tools_call_result(8, body)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match @mcp.parse_tools_call_result(json) {
    Some(parsed) => {
      assert_eq(parsed.is_error, true)
      assert_eq(@mcp.extract_text_content(parsed), "boom")
    }
    None => fail("parse failed")
  }
}

///|
test "chat_response_to_tools_call_result: non-json falls back to text" {
  let result = chat_response_to_tools_call_result(9, "raw text")
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match @mcp.parse_tools_call_result(json) {
    Some(parsed) => {
      assert_eq(parsed.is_error, false)
      assert_eq(@mcp.extract_text_content(parsed), "raw text")
    }
    None => fail("parse failed")
  }
}

// =============================================================================
// Full MCP IO flow tests (fixture-based)
// =============================================================================

///|
test "IO flow: initialize → tools/list → tools/call roundtrip" {
  // Simulate the MCP session lifecycle our server handles.
  // Step 1: Client sends initialize — verify response is parseable
  let init_response = build_initialize_result(1)
  let init_json = @json.parse(init_response) catch {
    _ => fail("invalid init response")
  }
  match @jsonrpc.RpcResponse::from_json(init_json) {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_true(r.error is None)
    }
    None => fail("couldn't parse as RpcResponse")
  }
  // Step 2: Client sends tools/list — verify tools are parseable
  let tools = [
    model_to_mcp_tool("gpt-4o", "GPT-4o", "openai"),
    model_to_mcp_tool("claude-sonnet-4-20250514", "Claude Sonnet", "anthropic"),
    model_to_mcp_tool("gemini-2.0-flash", "Gemini Flash", "google"),
  ]
  let list_response = build_tools_list_result(2, tools)
  let list_json = @json.parse(list_response) catch {
    _ => fail("invalid list response")
  }
  let parsed_tools = @mcp.parse_tools_list_response(list_json)
  assert_eq(parsed_tools.length(), 3)
  assert_eq(parsed_tools[0].name, "gpt-4o")
  assert_eq(parsed_tools[1].name, "claude-sonnet-4-20250514")
  assert_eq(parsed_tools[2].name, "gemini-2.0-flash")
  // Step 3: Client sends tools/call — verify result is parseable
  let call_result = build_tools_call_result(3, "The answer is 42.", false)
  let call_json = @json.parse(call_result) catch {
    _ => fail("invalid call result")
  }
  let parsed_result = @mcp.parse_tools_call_result(call_json)
  match parsed_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      let text = @mcp.extract_text_content(r)
      assert_eq(text, "The answer is 42.")
    }
    None => fail("couldn't parse tools/call result")
  }
}

///|
test "IO flow: client-side parser can consume server-side responses" {
  // Verify that session.mbt's client-side parsers (used to talk to
  // `claude mcp serve`) can parse our server-side responses.
  // This proves wire compatibility.

  // tools/list roundtrip: our server → client parser
  let tools = [model_to_mcp_tool("gpt-4o", "GPT-4o", "openai")]
  let server_response = build_tools_list_result(2, tools)
  let json = @json.parse(server_response) catch { _ => fail("invalid json") }
  let client_parsed = @mcp.parse_tools_list_response(json)
  assert_eq(client_parsed.length(), 1)
  assert_eq(client_parsed[0].name, "gpt-4o")
  // Verify it can be used to update a session
  let session = ClaudeMcpSession::new()
  let updated = update_session_tools(session, client_parsed)
  assert_eq(updated.tools.length(), 1)
  assert_eq(updated.tools[0].name, "gpt-4o")

  // tools/call roundtrip: our server → client parser
  let call_response = build_tools_call_result(3, "Hello from gateway", false)
  let call_json = @json.parse(call_response) catch { _ => fail("invalid json") }
  let call_result = @mcp.parse_tools_call_result(call_json)
  match call_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      // Client-side tools_result_to_chat should be able to convert this
      let chat = tools_result_to_chat(call_response)
      let chat_json = @json.parse(chat) catch { _ => fail("invalid chat json") }
      match chat_json {
        { "choices": [{ "message": { "content": String(c), .. }, .. }, ..], .. } =>
          assert_eq(c, "Hello from gateway")
        _ => fail("tools_result_to_chat failed: " + chat)
      }
    }
    None => fail("parse failed")
  }
}

///|
test "IO flow: tools_call_params_to_chat_request is valid OpenAI for all providers" {
  let params_with_system : Json = {
    "name": "gpt-4o",
    "arguments": {
      "prompt": "Hello",
      "system": "Be helpful",
      "max_tokens": 2048,
    },
  }
  match tools_call_params_to_chat_request(Some(params_with_system)) {
    Some(request) => {
      let json = @json.parse(request.body) catch { _ => fail("invalid json") }
      match json {
        {
          "model": String(_),
          "messages": Array(msgs),
          "max_tokens": Number(_),
          ..
        } => {
          assert_true(msgs.length() > 0)
          match msgs[0] {
            { "role": String("system"), "content": String(_), .. } => ()
            _ => fail("expected system message first")
          }
        }
        _ => fail("not valid OpenAI request body")
      }
    }
    None => fail("expected request")
  }
  let params_without_system : Json = {
    "name": "claude-sonnet",
    "arguments": { "prompt": "Hello", "max_tokens": 1024 },
  }
  match tools_call_params_to_chat_request(Some(params_without_system)) {
    Some(request) => {
      let json = @json.parse(request.body) catch { _ => fail("invalid json") }
      match json {
        { "messages": Array(msgs), .. } => {
          assert_eq(msgs.length(), 1)
          match msgs[0] {
            { "role": String("user"), .. } => ()
            _ => fail("expected user message")
          }
        }
        _ => fail("unexpected structure")
      }
    }
    None => fail("expected request")
  }
}
