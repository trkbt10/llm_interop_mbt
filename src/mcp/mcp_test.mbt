///|
/// Exhaustive tests for pure MCP protocol layer
/// Verifies MCP layer is application-agnostic
/// Ref: https://modelcontextprotocol.io/specification/2025-03-26

// =============================================================================
// build_initialize_request
// =============================================================================

///|
test "build_initialize_request: format" {
  let msg = build_initialize_request(1, "test-client", "0.1.0")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "method": String("initialize"),
      ..
    } => assert_eq(id.to_int(), 1)
    _ => fail("Invalid format")
  }
}

///|
test "build_initialize_request: client info" {
  let msg = build_initialize_request(1, "my-app", "2.0.0")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "params": {
        "clientInfo": { "name": String(n), "version": String(v), .. },
        ..
      },
      ..
    } => {
      assert_eq(n, "my-app")
      assert_eq(v, "2.0.0")
    }
    _ => fail("Missing clientInfo")
  }
}

///|
test "build_initialize_request: protocol version" {
  let msg = build_initialize_request(1, "x", "0")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "protocolVersion": String(pv), .. }, .. } =>
      assert_eq(pv, "2025-03-26")
    _ => fail("Missing protocolVersion")
  }
}

///|
test "build_initialize_request: capabilities present" {
  let msg = build_initialize_request(1, "x", "0")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
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
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "method": String("notifications/initialized"),
      ..
    } => ()
    _ => fail("Invalid format")
  }
}

///|
test "build_initialized_notification: no id" {
  let msg = build_initialized_notification()
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
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
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "method": String("tools/list"),
      ..
    } => assert_eq(id.to_int(), 5)
    _ => fail("Invalid format")
  }
}

///|
test "build_tools_list_request: no params" {
  let msg = build_tools_list_request(1)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
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
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "method": String("tools/call"),
      ..
    } => assert_eq(id.to_int(), 3)
    _ => fail("Invalid format")
  }
  match json {
    {
      "params": {
        "name": String(n),
        "arguments": { "file_path": String(fp), .. },
        ..
      },
      ..
    } => {
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
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "params": {
        "name": String("Bash"),
        "arguments": { "command": String(c), .. },
        ..
      },
      ..
    } => assert_eq(c, "echo 'hello world'")
    _ => fail("Complex arguments not preserved")
  }
}

///|
test "build_tools_call_request: empty arguments" {
  let msg = build_tools_call_request(1, "EmptyTool", Json::object({}))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "params": { "name": String("EmptyTool"), "arguments": Object(obj), .. },
      ..
    } => assert_eq(obj.length(), 0)
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
    "inputSchema": {
      "type": "object",
      "properties": { "file_path": { "type": "string" } },
    },
  }
  match McpToolDefinition::from_json(json) {
    Some(t) => {
      assert_eq(t.name, "Read")
      assert_eq(t.description, "Reads a file from the filesystem")
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
      match t.input_schema {
        Object(obj) => assert_eq(obj.length(), 0)
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
// McpContentItem::from_json — all 4 MCP content types
// Ref: https://modelcontextprotocol.io/specification/2025-03-26/server/tools
// =============================================================================

///|
test "McpContentItem::from_json: TextContent" {
  let json : Json = { "type": "text", "text": "hello world" }
  match McpContentItem::from_json(json) {
    Some(Text(text)) => assert_eq(text, "hello world")
    _ => fail("Failed to parse TextContent")
  }
}

///|
test "McpContentItem::from_json: ImageContent" {
  // Ref: {"type":"image","data":"base64...","mimeType":"image/png"}
  let json : Json = {
    "type": "image",
    "data": "iVBORw0KGgo=",
    "mimeType": "image/png",
  }
  match McpContentItem::from_json(json) {
    Some(Image(data~, mime_type~)) => {
      assert_eq(data, "iVBORw0KGgo=")
      assert_eq(mime_type, "image/png")
    }
    _ => fail("Failed to parse ImageContent")
  }
}

///|
test "McpContentItem::from_json: AudioContent" {
  // Ref: {"type":"audio","data":"base64...","mimeType":"audio/wav"}
  let json : Json = {
    "type": "audio",
    "data": "UklGR...",
    "mimeType": "audio/wav",
  }
  match McpContentItem::from_json(json) {
    Some(Audio(data~, mime_type~)) => {
      assert_eq(data, "UklGR...")
      assert_eq(mime_type, "audio/wav")
    }
    _ => fail("Failed to parse AudioContent")
  }
}

///|
test "McpContentItem::from_json: EmbeddedResource" {
  // Ref: {"type":"resource","resource":{"uri":"resource://example","mimeType":"text/plain","text":"content"}}
  let json : Json = {
    "type": "resource",
    "resource": {
      "uri": "resource://example",
      "mimeType": "text/plain",
      "text": "resource content",
    },
  }
  match McpContentItem::from_json(json) {
    Some(Resource(uri~, mime_type~, text~)) => {
      assert_eq(uri, "resource://example")
      assert_eq(mime_type, Some("text/plain"))
      assert_eq(text, Some("resource content"))
    }
    _ => fail("Failed to parse EmbeddedResource")
  }
}

///|
test "McpContentItem::from_json: EmbeddedResource minimal" {
  let json : Json = {
    "type": "resource",
    "resource": { "uri": "file:///tmp/data" },
  }
  match McpContentItem::from_json(json) {
    Some(Resource(uri~, mime_type~, text~)) => {
      assert_eq(uri, "file:///tmp/data")
      assert_eq(mime_type, None)
      assert_eq(text, None)
    }
    _ => fail("Failed to parse minimal resource")
  }
}

///|
test "McpContentItem::from_json: EmbeddedResource missing uri defaults to empty string" {
  let json : Json = {
    "type": "resource",
    "resource": { "mimeType": "text/plain", "text": "content only" },
  }
  match McpContentItem::from_json(json) {
    Some(Resource(uri~, mime_type~, text~)) => {
      assert_eq(uri, "")
      assert_eq(mime_type, Some("text/plain"))
      assert_eq(text, Some("content only"))
    }
    _ => fail("Should parse resource with empty fallback uri")
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
    Some(Text(text)) => assert_eq(text, "")
    _ => fail("Should parse empty text")
  }
}

///|
test "McpContentItem::from_json: image missing mimeType falls through to text fallback" {
  // Image without mimeType doesn't match ImageContent pattern,
  // falls to fallback that checks for text field
  let json : Json = { "type": "image", "data": "base64..." }
  // No mimeType → doesn't match Image pattern
  // No text field → returns None
  assert_eq(McpContentItem::from_json(json), None)
}

///|
test "McpContentItem::from_json: unknown type with text uses fallback Text" {
  let json : Json = { "type": "notice", "text": "fallback text" }
  match McpContentItem::from_json(json) {
    Some(Text(text)) => assert_eq(text, "fallback text")
    _ => fail("Expected text fallback")
  }
}

// =============================================================================
// McpContentItem::to_json roundtrip
// =============================================================================

///|
test "McpContentItem::to_json roundtrip: Text" {
  let item = McpContentItem::Text("hello")
  let json = item.to_json()
  match McpContentItem::from_json(json) {
    Some(Text(text)) => assert_eq(text, "hello")
    _ => fail("Roundtrip failed for Text")
  }
}

///|
test "McpContentItem::to_json roundtrip: Image" {
  let item = McpContentItem::Image(data="abc", mime_type="image/png")
  let json = item.to_json()
  match McpContentItem::from_json(json) {
    Some(Image(data~, mime_type~)) => {
      assert_eq(data, "abc")
      assert_eq(mime_type, "image/png")
    }
    _ => fail("Roundtrip failed for Image")
  }
}

///|
test "McpContentItem::to_json roundtrip: Audio" {
  let item = McpContentItem::Audio(data="xyz", mime_type="audio/wav")
  let json = item.to_json()
  match McpContentItem::from_json(json) {
    Some(Audio(data~, mime_type~)) => {
      assert_eq(data, "xyz")
      assert_eq(mime_type, "audio/wav")
    }
    _ => fail("Roundtrip failed for Audio")
  }
}

///|
test "McpContentItem::to_json roundtrip: Resource" {
  let item = McpContentItem::Resource(
    uri="file:///test",
    mime_type=Some("text/plain"),
    text=Some("content"),
  )
  let json = item.to_json()
  match McpContentItem::from_json(json) {
    Some(Resource(uri~, mime_type~, text~)) => {
      assert_eq(uri, "file:///test")
      assert_eq(mime_type, Some("text/plain"))
      assert_eq(text, Some("content"))
    }
    _ => fail("Roundtrip failed for Resource")
  }
}

///|
test "McpContentItem::to_json roundtrip: Resource without optional fields" {
  let item = McpContentItem::Resource(
    uri="resource://opaque",
    mime_type=None,
    text=None,
  )
  let json = item.to_json()
  match McpContentItem::from_json(json) {
    Some(Resource(uri~, mime_type~, text~)) => {
      assert_eq(uri, "resource://opaque")
      assert_eq(mime_type, None)
      assert_eq(text, None)
    }
    _ => fail("Roundtrip failed for minimal Resource")
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
    "result": { "content": [{ "type": "text", "text": "file contents" }] },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 1)
      match result.content[0] {
        Text(text) => assert_eq(text, "file contents")
        _ => fail("Expected Text")
      }
    }
    None => fail("Failed to parse")
  }
}

///|
test "parse_tools_call_result: mixed content types" {
  let json : Json = {
    "result": {
      "content": [
        { "type": "text", "text": "description" },
        { "type": "image", "data": "base64img", "mimeType": "image/png" },
        { "type": "audio", "data": "base64audio", "mimeType": "audio/wav" },
      ],
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 3)
      match result.content[1] {
        Image(data~, mime_type~) => {
          assert_eq(data, "base64img")
          assert_eq(mime_type, "image/png")
        }
        _ => fail("Expected Image")
      }
      match result.content[2] {
        Audio(data~, mime_type~) => {
          assert_eq(data, "base64audio")
          assert_eq(mime_type, "audio/wav")
        }
        _ => fail("Expected Audio")
      }
    }
    None => fail("Failed to parse multi-type result")
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
      match result.content[0] {
        Text(text) => assert_eq(text, "Permission denied")
        _ => fail("Expected Text")
      }
    }
    None => fail("Failed to parse error result")
  }
}

///|
test "parse_tools_call_result: empty content" {
  let json : Json = { "result": { "content": Json::array([]) } }
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
    "result": { "content": [{ "type": "text", "text": "ok" }] },
  }
  match parse_tools_call_result(json) {
    Some(result) => assert_eq(result.is_error, false)
    None => fail("Failed to parse")
  }
}

///|
test "parse_tools_call_result: malformed content items are skipped" {
  let json : Json = {
    "result": {
      "content": [
        { "type": "text", "text": "ok" },
        { "type": "image", "data": "missing mime type" },
      ],
    },
  }
  match parse_tools_call_result(json) {
    Some(result) => {
      assert_eq(result.is_error, false)
      assert_eq(result.content.length(), 1)
    }
    None => fail("Failed to parse")
  }
}

// =============================================================================
// extract_text_content
// =============================================================================

///|
test "extract_text_content: single text" {
  let result : McpToolCallResult = {
    content: [McpContentItem::Text("hello")],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "hello")
}

///|
test "extract_text_content: multiple text joined" {
  let result : McpToolCallResult = {
    content: [
      McpContentItem::Text("line1"),
      McpContentItem::Text("line2"),
      McpContentItem::Text("line3"),
    ],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "line1\nline2\nline3")
}

///|
test "extract_text_content: filters non-text" {
  let result : McpToolCallResult = {
    content: [
      McpContentItem::Text("before"),
      McpContentItem::Image(data="img", mime_type="image/png"),
      McpContentItem::Text("after"),
    ],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "before\nafter")
}

///|
test "extract_text_content: includes resource text" {
  let result : McpToolCallResult = {
    content: [
      McpContentItem::Text("intro"),
      McpContentItem::Resource(
        uri="file:///tmp",
        mime_type=Some("text/plain"),
        text=Some("resource data"),
      ),
    ],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "intro\nresource data")
}

///|
test "extract_text_content: empty" {
  let result : McpToolCallResult = { content: [], is_error: false }
  assert_eq(extract_text_content(result), "")
}

///|
test "extract_text_content: only non-text" {
  let result : McpToolCallResult = {
    content: [McpContentItem::Image(data="data", mime_type="image/png")],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "")
}

///|
test "extract_text_content: multiline text item" {
  let result : McpToolCallResult = {
    content: [McpContentItem::Text("line1\nline2\nline3")],
    is_error: false,
  }
  assert_eq(extract_text_content(result), "line1\nline2\nline3")
}
