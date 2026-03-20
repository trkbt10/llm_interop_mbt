///|
/// Anthropic dialect protocol tests

// Test fixtures
let test_model_anthropic : String = "claude-3-opus-20240229"

// =============================================================================
// Message Conversion Tests (Anthropic Format)
// =============================================================================

///|
test "message_to_json converts System message" {
  let msg = @types.ModelMessage::System("You are Claude")
  let json = message_to_json(msg)
  match json {
    { "role": "system", "content": "You are Claude", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_json converts Assistant with tool_use" {
  let calls = [
    @types.ToolCallRequest::new(id="toolu_123", name="search", arguments={
      "query": "MoonBit",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  let json = message_to_json(msg)
  match json {
    { "role": "assistant", "content": Array(content), .. } => {
      inspect(content.length(), content="1")
      match content[0] {
        { "type": "tool_use", "id": "toolu_123", "name": "search", .. } => ()
        _ => fail("Unexpected tool_use format")
      }
    }
    _ => fail("Unexpected JSON format")
  }
}

// =============================================================================
// Tool Conversion Tests (Anthropic Format)
// =============================================================================

///|
test "tool_to_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="calculator",
    description="Calculate math",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_json(tool)
  match json {
    {
      "name": "calculator",
      "description": "Calculate math",
      "input_schema": _,
      ..
    } => ()
    _ => fail("Unexpected JSON format")
  }
}

// =============================================================================
// Request Body Builder Tests (Anthropic Format)
// =============================================================================

///|
test "build_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are Claude"),
    @types.ModelMessage::User(content="Hello", name=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_body(
    test_model_anthropic,
    messages,
    tools,
    max_tokens=Some(4096),
  )
  match body {
    {
      "model": String(model),
      "max_tokens": Number(mt, ..),
      "messages": Array(msgs),
      "system": String(sys),
      ..
    } => {
      assert_eq(model, test_model_anthropic)
      inspect(mt, content="4096")
      inspect(msgs.length(), content="1") // System excluded from messages
      inspect(sys, content="You are Claude")
    }
    _ => fail("Unexpected body format")
  }
}

// =============================================================================
// Response Parser Tests (Anthropic Format)
// =============================================================================

///|
test "parse_response parses text response" {
  let json : Json = {
    "content": Json::array([{ "type": "text", "text": "Hello from Claude!" }]),
    "stop_reason": "end_turn",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello from Claude!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_response parses tool_use response" {
  let json : Json = {
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_abc",
        "name": "search",
        "input": { "query": "MoonBit" },
      },
    ]),
    "stop_reason": "tool_use",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="search")
    }
    _ => fail("Expected ToolCalls response")
  }
}
