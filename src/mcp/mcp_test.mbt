///|
/// Exhaustive tests for pure MCP protocol layer
/// Verifies MCP layer is application-agnostic

// =============================================================================
// build_initialize_request
// =============================================================================

///|
test "build_initialize_request: format" {
  let msg = build_initialize_request(1, "test-client", "0.1.0")
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "id": Number(id, ..), "method": String("initialize"), .. } =>
      assert_eq(id.to_int(), 1)
    _ => fail("Invalid format")
  }
}

///|
test "build_initialize_request: client info" {
  let msg = build_initialize_request(1, "my-app", "2.0.0")
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "clientInfo": { "name": String(n), "version": String(v), .. }, .. }, .. } => {
      assert_eq(n, "my-app")
      assert_eq(v, "2.0.0")
    }
    _ => fail("Missing clientInfo")
  }
}

///|
test "build_initialize_request: protocol version" {
  let msg = build_initialize_request(1, "x", "0")
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "protocolVersion": String(pv), .. }, .. } =>
      assert_eq(pv, "2025-03-26")
    _ => fail("Missing protocolVersion")
  }
}

///|
test "build_initialize_request: capabilities present" {
  let msg = build_initialize_request(1, "x", "0")
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "capabilities": Object(_), .. }, .. } => ()
    _ => fail("Missing capabilities")
  }
}

// =============================================================================
// build_initialized_notification
// =============================================================================

///|
test "build_initialized_notification: format" {
  let msg = build_initialized_notification()
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "method": String("notifications/initialized"), .. } =>
      ()
    _ => fail("Invalid format")
  }
}

///|
test "build_initialized_notification: no id" {
  let msg = build_initialized_notification()
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "id": _, .. } => fail("Should not have id")
    _ => ()
  }
}

// =============================================================================
// build_tools_list_request
// =============================================================================

///|
test "build_tools_list_request: format" {
  let msg = build_tools_list_request(5)
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "id": Number(id, ..), "method": String("tools/list"), .. } =>
      assert_eq(id.to_int(), 5)
    _ => fail("Invalid format")
  }
}

///|
test "build_tools_list_request: no params" {
  let msg = build_tools_list_request(1)
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": _, .. } => fail("tools/list should not have params")
    _ => ()
  }
}

// =============================================================================
// build_tools_call_request
// =============================================================================

///|
test "build_tools_call_request: basic" {
  let args : Json = { "file_path": "/tmp/test.txt" }
  let msg = build_tools_call_request(3, "Read", args)
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "id": Number(id, ..), "method": String("tools/call"), .. } =>
      assert_eq(id.to_int(), 3)
    _ => fail("Invalid format")
  }
  match json {
    { "params": { "name": String(n), "arguments": { "file_path": String(fp), .. }, .. }, .. } => {
      assert_eq(n, "Read")
      assert_eq(fp, "/tmp/test.txt")
    }
    _ => fail("Invalid params")
  }
}

///|
test "build_tools_call_request: complex arguments" {
  let args : Json = {
    "command": "echo 'hello world'",
    "timeout": 30000,
    "env": { "PATH": "/usr/bin" },
  }
  let msg = build_tools_call_request(1, "Bash", args)
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "name": String("Bash"), "arguments": { "command": String(c), .. }, .. }, .. } =>
      assert_eq(c, "echo 'hello world'")
    _ => fail("Complex arguments not preserved")
  }
}

///|
test "build_tools_call_request: empty arguments" {
  let msg = build_tools_call_request(1, "EmptyTool", Json::object({}))
  let json = try { @json.parse(msg) } catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "name": String("EmptyTool"), "arguments": Object(obj), .. }, .. } =>
      assert_eq(obj.size(), 0)
    _ => fail("Empty arguments not preserved")
  }
}

// =============================================================================
// McpToolDefinition::from_json
// =============================================================================

///|
test "McpToolDefinition::from_json: full" {
  let json : Json = {
    "name": "Read",
    "description": "Reads a file from the filesystem",
    "inputSchema": { "type": "object", "properties": { "file_path": { "type": "string" } } },
  }
  match McpToolDefinition::from_json(json) {
    Some(t) => {
      assert_eq(t.name, "Read")
      assert_eq(t.description, "Reads a file from the filesystem")
      // inputSchema should be preserved
      match t.input_schema {
        { "type": String("object"), .. } => ()
        _ => fail("inputSchema not preserved")
      }
    }
    None => fail("Failed to parse")
  }
}

///|
test "McpToolDefinition::from_json: missing description" {
  let json : Json = { "name": "Bash" }
  match McpToolDefinition::from_json(json) {
    Some(t) => {
      assert_eq(t.name, "Bash")
      assert_eq(t.description, "")
    }
    None => fail("Should parse with missing description")
  }
}

///|
test "McpToolDefinition::from_json: missing inputSchema" {
  let json : Json = { "name": "Test", "description": "A test tool" }
  match McpToolDefinition::from_json(json) {
    Some(t) => {
      assert_eq(t.name, "Test")
      // inputSchema should default to empty object
      match t.input_schema {
        Object(obj) => assert_eq(obj.size(), 0)
        _ => fail("Default inputSchema should be empty object")
      }
    }
    None => fail("Should parse with missing inputSchema")
  }
}

///|
test "McpToolDefinition::from_json: invalid (no name)" {
  assert_eq(McpToolDefinition::from_json({ "description": "no name" }), None)
}

///|
test "McpToolDefinition::from_json: invalid (empty)" {
  assert_eq(McpToolDefinition::from_json(Json::object({})), None)
}

///|
test "McpToolDefinition::from_json: invalid (not object)" {
  assert_eq(McpToolDefinition::from_json(Json::string("hello")), None)
}

// =============================================================================
// McpContentItem::from_json
// =============================================================================

///|
test "McpContentItem::from_json: text" {
  let json : Json = { "type": "text", "text": "hello world" }
  match McpContentItem::from_json(json) {
    Some(c) => {
      assert_eq(c.kind, "text")
      assert_eq(c.text, "hello world")
    }
    None => fail("Failed to parse")
  }
}

///|
test "McpContentItem::from_json: image" {
  let json : Json = { "type": "image", "data": "base64..." }
  match McpContentItem::from_json(json) {
    Some(c) => {
      assert_eq(c.kind, "image")
      assert_eq(c.text, "") // No text field for image
    }
    None => fail("Failed to parse image")
  }
}

///|
test "McpContentItem::from_json: resource" {
  let json : Json = { "type": "resource", "text": "resource content" }
  match McpContentItem::from_json(json) {
    Some(c) => {
      assert_eq(c.kind, "resource")
      assert_eq(c.text, "resource content")
    }
    None => fail("Failed to parse resource")
  }
}

///|
test "McpContentItem::from_json: invalid (no type)" {
  assert_eq(McpContentItem::from_json({ "text": "no type" }), None)
}

///|
test "McpContentItem::from_json: empty text" {
  let json : Json = { "type": "text", "text": "" }
  match McpContentItem::from_json(json) {
    Some(c) => assert_eq(c.text, "")
    None => fail("Should parse empty text")
  }
}

// =============================================================================
// parse_tools_list_response
// =============================================================================

///|
test "parse_tools_list_response: multiple tools" {
  let json : Json = {
    "result": {
      "tools": [
        { "name": "Read", "description": "Read a file", "inputSchema": {} },
        { "name": "Write", "description": "Write a file", "inputSchema": {} },
        { "name": "Bash", "description": "Run command", "inputSchema": {} },
      ],
    },
  }
  let tools = parse_tools_list_response(json)
  assert_eq(tools.length(), 3)
  assert_eq(tools[0].name, "Read")
  assert_eq(tools[1].name, "Write")
  assert_eq(tools[2].name, "Bash")
}

///|
test "parse_tools_list_response: empty list" {
  let json : Json = { "result": { "tools": Json::array([]) } }
  let tools = parse_tools_list_response(json)
  assert_eq(tools.length(), 0)
}

///|
test "parse_tools_list_response: no result" {
  let tools = parse_tools_list_response(Json::object({}))
  assert_eq(tools.length(), 0)
}

///|
test "parse_tools_list_response: malformed items skipped" {
  let json : Json = {
    "result": {
      "tools": [
        { "name": "Valid", "description": "ok" },
        { "invalid": true },
        { "name": "AlsoValid" },
      ],
    },
  }
  let tools = parse_tools_list_response(json)
  assert_eq(tools.length(), 2)
  assert_eq(tools[0].name, "Valid")
  assert_eq(tools[1].name, "AlsoValid")
}

///|
test "parse_tools_list_response: not an object" {
  let tools = parse_tools_list_response(Json::null())
  assert_eq(tools.length(), 0)
}

// =============================================================================
// parse_tools_call_result
// =============================================================================

///|
test "parse_tools_call_result: success single text" {
  let json : Json = {
    "result": {
      "content": [{ "type": "text", "text": "file contents" }],
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 1)
      assert_eq(result.content[0].kind, "text")
      assert_eq(result.content[0].text, "file contents")
    }
    None => fail("Failed to parse")
  }
}

///|
test "parse_tools_call_result: success multiple items" {
  let json : Json = {
    "result": {
      "content": [
        { "type": "text", "text": "line1" },
        { "type": "text", "text": "line2" },
        { "type": "image", "data": "..." },
      ],
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 3)
    }
    None => fail("Failed to parse multi-item result")
  }
}

///|
test "parse_tools_call_result: error" {
  let json : Json = {
    "result": {
      "content": [{ "type": "text", "text": "Permission denied" }],
      "isError": true,
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, true)
      assert_eq(result.content[0].text, "Permission denied")
    }
    None => fail("Failed to parse error result")
  }
}

///|
test "parse_tools_call_result: empty content" {
  let json : Json = {
    "result": { "content": Json::array([]) },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 0)
    }
    None => fail("Failed to parse empty content")
  }
}

///|
test "parse_tools_call_result: no result key" {
  assert_eq(parse_tools_call_result(Json::object({})), None)
}

///|
test "parse_tools_call_result: isError false explicitly" {
  let json : Json = {
    "result": {
      "content": [{ "type": "text", "text": "ok" }],
      "isError": false,
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => assert_eq(result.is_error, false)
    None => fail("Failed to parse")
  }
}

///|
test "parse_tools_call_result: isError absent means false" {
  let json : Json = {
    "result": {
      "content": [{ "type": "text", "text": "ok" }],
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => assert_eq(result.is_error, false)
    None => fail("Failed to parse")
  }
}

// =============================================================================
// extract_text_content
// =============================================================================

///|
test "extract_text_content: single text" {
  let result : McpToolCallResult = {
    content: [{ kind: "text", text: "hello" }],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "hello")
}

///|
test "extract_text_content: multiple text joined" {
  let result : McpToolCallResult = {
    content: [
      { kind: "text", text: "line1" },
      { kind: "text", text: "line2" },
      { kind: "text", text: "line3" },
    ],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "line1\nline2\nline3")
}

///|
test "extract_text_content: filters non-text" {
  let result : McpToolCallResult = {
    content: [
      { kind: "text", text: "before" },
      { kind: "image", text: "" },
      { kind: "resource", text: "resource data" },
      { kind: "text", text: "after" },
    ],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "before\nafter")
}

///|
test "extract_text_content: empty" {
  let result : McpToolCallResult = { content: [], is_error: false }
  assert_eq(extract_text_content(result), "")
}

///|
test "extract_text_content: only non-text" {
  let result : McpToolCallResult = {
    content: [{ kind: "image", text: "data" }],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "")
}

///|
test "extract_text_content: multiline text item" {
  let result : McpToolCallResult = {
    content: [{ kind: "text", text: "line1\nline2\nline3" }],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "line1\nline2\nline3")
}
