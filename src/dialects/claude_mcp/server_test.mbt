///|
/// Tests for MCP server-side responses and request parsing

// =============================================================================
// build_initialize_result
// =============================================================================

///|
test "build_initialize_result: valid JSON-RPC response" {
  let result = build_initialize_result(1)
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
  match json {
    { "id": Number(id, ..), .. } => assert_eq(id.to_int(), 42)
    _ => fail("missing id")
  }
}

///|
test "build_initialize_result: matches fixture structure" {
  // Verify our server response has the same structure as the real
  // `claude mcp serve` initialize response in fixtures
  let fixture = @utils.read_testdata("testdata/claude_mcp/initialize_response.json")
  let fixture_json = try { @json.parse(fixture) } catch {
    _ => fail("invalid fixture")
  }
  let our_result = build_initialize_result(1)
  let our_json = try { @json.parse(our_result) } catch {
    _ => fail("invalid json")
  }
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
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
  let json = try { @json.parse(response) } catch { _ => fail("invalid json") }
  let parsed = @mcp.parse_tools_list_response(json)
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].name, "gpt-4o")
  assert_eq(parsed[0].description, "GPT-4o")
}

///|
test "build_tools_list_result: matches fixture structure" {
  // Verify each tool has same shape as real `claude mcp serve` tools/list
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_list_response.json")
  let fixture_json = try { @json.parse(fixture) } catch {
    _ => fail("invalid fixture")
  }
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
  let our_tools = [
    model_to_mcp_tool("gpt-4o", "GPT-4o", "openai"),
  ]
  let our_response = build_tools_list_result(2, our_tools)
  let our_json = try { @json.parse(our_response) } catch {
    _ => fail("invalid json")
  }
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
  match json {
    {
      "id": Number(id, ..),
      "result": { "content": Array(items), .. },
      ..
    } => {
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
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
  let json = try { @json.parse(response) } catch { _ => fail("invalid json") }
  let parsed = @mcp.parse_tools_call_result(json)
  match parsed {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_eq(r.content.length(), 1)
      assert_eq(r.content[0].text, "test content")
    }
    None => fail("parse failed")
  }
}

///|
test "build_tools_call_result: matches fixture success structure" {
  // Compare with real `claude mcp serve` tools/call response fixture
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_read_response.json")
  let fixture_json = try { @json.parse(fixture) } catch {
    _ => fail("invalid fixture")
  }
  let fixture_result = @mcp.parse_tools_call_result(fixture_json)
  match fixture_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_true(r.content.length() > 0)
      assert_eq(r.content[0].kind, "text")
    }
    None => fail("failed to parse fixture")
  }
  // Our response should parse identically
  let our_response = build_tools_call_result(3, "Hello, world!\nThis is a test file.", false)
  let our_json = try { @json.parse(our_response) } catch {
    _ => fail("invalid json")
  }
  let our_result = @mcp.parse_tools_call_result(our_json)
  match our_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      assert_eq(r.content.length(), 1)
      assert_eq(r.content[0].kind, "text")
      assert_eq(r.content[0].text, "Hello, world!\nThis is a test file.")
    }
    None => fail("failed to parse our response")
  }
}

///|
test "build_tools_call_result: matches fixture error structure" {
  let fixture = @utils.read_testdata("testdata/claude_mcp/tools_call_error_response.json")
  let fixture_json = try { @json.parse(fixture) } catch {
    _ => fail("invalid fixture")
  }
  let fixture_result = @mcp.parse_tools_call_result(fixture_json)
  match fixture_result {
    Some(r) => {
      assert_eq(r.is_error, true)
      assert_true(r.content[0].text.contains("ENOENT"))
    }
    None => fail("failed to parse fixture")
  }
  // Our error response should parse the same way
  let our_response = build_tools_call_result(4, "Error: ENOENT: file not found", true)
  let our_json = try { @json.parse(our_response) } catch {
    _ => fail("invalid json")
  }
  let our_result = @mcp.parse_tools_call_result(our_json)
  match our_result {
    Some(r) => {
      assert_eq(r.is_error, true)
      assert_true(r.content[0].text.contains("ENOENT"))
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
  let json = try { @json.parse(result) } catch { _ => fail("invalid json") }
  match json {
    { "jsonrpc": String("2.0"), "id": Number(id, ..), "result": Object(obj), .. } => {
      assert_eq(id.to_int(), 5)
      assert_eq(obj.length(), 0)
    }
    _ => fail("unexpected structure")
  }
}

// =============================================================================
// parse_tools_call_params
// =============================================================================

///|
test "parse_tools_call_params: valid params" {
  let params : Json = { "name": "gpt-4o", "arguments": { "prompt": "Hello" } }
  match parse_tools_call_params(Some(params)) {
    Some(p) => {
      assert_eq(p.name, "gpt-4o")
      match p.arguments {
        { "prompt": String("Hello"), .. } => ()
        _ => fail("invalid arguments")
      }
    }
    None => fail("expected Some")
  }
}

///|
test "parse_tools_call_params: no arguments defaults to empty object" {
  let params : Json = { "name": "gpt-4o" }
  match parse_tools_call_params(Some(params)) {
    Some(p) => {
      assert_eq(p.name, "gpt-4o")
      match p.arguments {
        Object(obj) => assert_eq(obj.length(), 0)
        _ => fail("expected empty object")
      }
    }
    None => fail("expected Some")
  }
}

///|
test "parse_tools_call_params: None params" {
  assert_eq(parse_tools_call_params(None), None)
}

///|
test "parse_tools_call_params: missing name" {
  let params : Json = { "arguments": { "prompt": "Hello" } }
  assert_eq(parse_tools_call_params(Some(params)), None)
}

// =============================================================================
// extract_prompt_args
// =============================================================================

///|
test "extract_prompt_args: all fields" {
  let args : Json = {
    "prompt": "Say hello",
    "system": "You are helpful",
    "max_tokens": 1024,
  }
  let result = extract_prompt_args(args)
  assert_eq(result.prompt, "Say hello")
  assert_eq(result.system, "You are helpful")
  assert_eq(result.max_tokens, 1024)
}

///|
test "extract_prompt_args: prompt only" {
  let args : Json = { "prompt": "Hello" }
  let result = extract_prompt_args(args)
  assert_eq(result.prompt, "Hello")
  assert_eq(result.system, "")
  assert_eq(result.max_tokens, 4096)
}

///|
test "extract_prompt_args: empty object" {
  let result = extract_prompt_args(Json::object({}))
  assert_eq(result.prompt, "")
  assert_eq(result.system, "")
  assert_eq(result.max_tokens, 4096)
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

// =============================================================================
// build_chat_request
// =============================================================================

///|
test "build_chat_request: prompt only" {
  let body = build_chat_request("gpt-4o", "Hello", "", 4096)
  let json = try { @json.parse(body) } catch { _ => fail("invalid json") }
  match json {
    {
      "model": String("gpt-4o"),
      "messages": Array(msgs),
      "max_tokens": Number(mt, ..),
      "stream": False,
      ..
    } => {
      assert_eq(msgs.length(), 1) // user only, no system
      assert_eq(mt.to_int(), 4096)
      match msgs[0] {
        { "role": String("user"), "content": String("Hello"), .. } => ()
        _ => fail("invalid user message")
      }
    }
    _ => fail("unexpected structure: " + body)
  }
}

///|
test "build_chat_request: with system prompt" {
  let body = build_chat_request("claude-sonnet", "Hi", "Be helpful", 1024)
  let json = try { @json.parse(body) } catch { _ => fail("invalid json") }
  match json {
    { "messages": Array(msgs), "max_tokens": Number(mt, ..), .. } => {
      assert_eq(msgs.length(), 2) // system + user
      assert_eq(mt.to_int(), 1024)
      match msgs[0] {
        { "role": String("system"), "content": String("Be helpful"), .. } => ()
        _ => fail("invalid system message")
      }
      match msgs[1] {
        { "role": String("user"), "content": String("Hi"), .. } => ()
        _ => fail("invalid user message")
      }
    }
    _ => fail("unexpected structure")
  }
}

///|
test "build_chat_request: stream is always false" {
  let body = build_chat_request("gpt-4o", "test", "", 100)
  let json = try { @json.parse(body) } catch { _ => fail("invalid json") }
  match json {
    { "stream": False, .. } => ()
    _ => fail("expected stream: false")
  }
}

// =============================================================================
// extract_assistant_content
// =============================================================================

///|
test "extract_assistant_content: OpenAI format" {
  let body =
    #|{"choices":[{"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
  assert_eq(extract_assistant_content(body), "Hello!")
}

///|
test "extract_assistant_content: empty content" {
  let body =
    #|{"choices":[{"message":{"role":"assistant","content":""},"finish_reason":"stop"}]}
  assert_eq(extract_assistant_content(body), "")
}

///|
test "extract_assistant_content: non-JSON fallback" {
  assert_eq(extract_assistant_content("raw text"), "raw text")
}

///|
test "extract_assistant_content: no choices fallback" {
  let body =
    #|{"error":"something"}
  assert_eq(extract_assistant_content(body), body)
}

///|
test "extract_assistant_content: works with Anthropic-transformed response" {
  // Simulate what gateway transform_response produces when converting
  // Anthropic → OpenAI: an OpenAI-format response
  let anthropic_as_openai =
    #|{"id":"msg-123","object":"chat.completion","model":"claude-sonnet","choices":[{"index":0,"message":{"role":"assistant","content":"Bonjour!"},"finish_reason":"stop"}]}
  assert_eq(extract_assistant_content(anthropic_as_openai), "Bonjour!")
}

///|
test "extract_assistant_content: works with Gemini-transformed response" {
  // Simulate gateway transform_response Gemini → OpenAI output
  let gemini_as_openai =
    #|{"id":"gemini-resp","object":"chat.completion","model":"gemini-pro","choices":[{"index":0,"message":{"role":"assistant","content":"Hola!"},"finish_reason":"stop"}]}
  assert_eq(extract_assistant_content(gemini_as_openai), "Hola!")
}

// =============================================================================
// Full MCP IO flow tests (fixture-based)
// =============================================================================

///|
test "IO flow: initialize → tools/list → tools/call roundtrip" {
  // Simulate the MCP session lifecycle our server handles.
  // Step 1: Client sends initialize — verify response is parseable
  let init_response = build_initialize_result(1)
  let init_json = try { @json.parse(init_response) } catch {
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
  let list_json = try { @json.parse(list_response) } catch {
    _ => fail("invalid list response")
  }
  let parsed_tools = @mcp.parse_tools_list_response(list_json)
  assert_eq(parsed_tools.length(), 3)
  assert_eq(parsed_tools[0].name, "gpt-4o")
  assert_eq(parsed_tools[1].name, "claude-sonnet-4-20250514")
  assert_eq(parsed_tools[2].name, "gemini-2.0-flash")
  // Step 3: Client sends tools/call — verify result is parseable
  let call_result = build_tools_call_result(3, "The answer is 42.", false)
  let call_json = try { @json.parse(call_result) } catch {
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
  let tools = [
    model_to_mcp_tool("gpt-4o", "GPT-4o", "openai"),
  ]
  let server_response = build_tools_list_result(2, tools)
  let json = try { @json.parse(server_response) } catch {
    _ => fail("invalid json")
  }
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
  let call_json = try { @json.parse(call_response) } catch {
    _ => fail("invalid json")
  }
  let call_result = @mcp.parse_tools_call_result(call_json)
  match call_result {
    Some(r) => {
      assert_eq(r.is_error, false)
      // Client-side tools_result_to_chat should be able to convert this
      let chat = tools_result_to_chat(call_response)
      let chat_json = try { @json.parse(chat) } catch {
        _ => fail("invalid chat json")
      }
      match chat_json {
        {
          "choices": [
            { "message": { "content": String(c), .. }, .. },
            ..,
          ],
          ..
        } => assert_eq(c, "Hello from gateway")
        _ => fail("tools_result_to_chat failed: " + chat)
      }
    }
    None => fail("parse failed")
  }
}

///|
test "IO flow: build_chat_request is valid OpenAI for all providers" {
  // The key insight: build_chat_request produces OpenAI format,
  // and the gateway transform_request converts it to Anthropic/Gemini/etc.
  // Verify the request body is valid for the OpenAI transform entry point.
  let body = build_chat_request("gpt-4o", "Hello", "Be helpful", 2048)
  let json = try { @json.parse(body) } catch { _ => fail("invalid json") }
  // Must have model, messages, max_tokens — the minimum for OpenAI
  match json {
    {
      "model": String(_),
      "messages": Array(msgs),
      "max_tokens": Number(_),
      ..
    } => {
      assert_true(msgs.length() > 0)
      // First message should be system
      match msgs[0] {
        { "role": String("system"), "content": String(_), .. } => ()
        _ => fail("expected system message first")
      }
    }
    _ => fail("not valid OpenAI request body")
  }
  // Without system
  let body2 = build_chat_request("claude-sonnet", "Hello", "", 1024)
  let json2 = try { @json.parse(body2) } catch { _ => fail("invalid json") }
  match json2 {
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
