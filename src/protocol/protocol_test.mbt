///|
/// Protocol package tests

// Test fixtures
let test_model_openai : String = "gpt-4"

///|
let test_model_openai_responses : String = "gpt-4o"

///|
let test_model_anthropic : String = "claude-3-opus-20240229"

///|
let test_response_id : String = "resp_123"

// =============================================================================
// Message Conversion Tests (OpenAI Format)
// =============================================================================

///|
test "message_to_openai_json converts System message" {
  let msg = @types.ModelMessage::System("You are a helpful assistant")
  let json = message_to_openai_json(msg)
  match json {
    { "role": "system", "content": "You are a helpful assistant", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_openai_json converts User message" {
  let msg = @types.ModelMessage::User(content="Hello", name=None)
  let json = message_to_openai_json(msg)
  match json {
    { "role": "user", "content": "Hello", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_openai_json converts Assistant with tool_calls" {
  let calls = [
    @types.ToolCallRequest::new(id="call_123", name="get_weather", arguments={
      "city": "Tokyo",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  let json = message_to_openai_json(msg)
  match json {
    { "role": "assistant", "tool_calls": Array(tc), .. } => {
      inspect(tc.length(), content="1")
      match tc[0] {
        { "id": "call_123", "function": { "name": "get_weather", .. }, .. } =>
          ()
        _ => fail("Unexpected tool_call format")
      }
    }
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_openai_json converts ToolResult" {
  let msg = @types.ModelMessage::ToolResult(
    tool_call_id="call_123",
    content="Sunny, 25C",
  )
  let json = message_to_openai_json(msg)
  match json {
    { "role": "tool", "tool_call_id": "call_123", "content": "Sunny, 25C", .. } =>
      ()
    _ => fail("Unexpected JSON format")
  }
}

// =============================================================================
// Message Conversion Tests (Anthropic Format)
// =============================================================================

///|
test "message_to_anthropic_json converts System message" {
  let msg = @types.ModelMessage::System("You are Claude")
  let json = message_to_anthropic_json(msg)
  match json {
    { "role": "system", "content": "You are Claude", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_anthropic_json converts Assistant with tool_use" {
  let calls = [
    @types.ToolCallRequest::new(id="toolu_123", name="search", arguments={
      "query": "MoonBit",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  let json = message_to_anthropic_json(msg)
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
// Tool Conversion Tests
// =============================================================================

///|
test "tool_to_openai_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="get_weather",
    description="Get weather info",
    parameters={
      "type": "object",
      "properties": { "city": { "type": "string" } },
    },
  )
  let json = tool_to_openai_json(tool)
  match json {
    { "type": "function", "function": { "name": "get_weather", .. }, .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "tool_to_responses_api_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="search",
    description="Search the web",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_responses_api_json(tool)
  match json {
    {
      "type": "function",
      "name": "search",
      "description": "Search the web",
      ..
    } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "tool_to_anthropic_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="calculator",
    description="Calculate math",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_anthropic_json(tool)
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
// Request Body Builder Tests
// =============================================================================

///|
test "build_openai_chat_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are helpful"),
    @types.ModelMessage::User(content="Hello", name=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_openai_chat_body(
    test_model_openai,
    messages,
    tools,
    max_tokens=Some(1000),
  )
  match body {
    {
      "model": String(model),
      "messages": Array(msgs),
      "max_tokens": Number(mt, ..),
      ..
    } => {
      assert_eq(model, test_model_openai)
      inspect(msgs.length(), content="2")
      inspect(mt, content="1000")
    }
    _ => fail("Unexpected body format")
  }
}

///|
test "build_responses_api_body creates valid body" {
  let messages = [
    @types.ModelMessage::User(content="What time is it?", name=None),
  ]
  let tools = [
    @types.ToolDefinition::new(name="datetime", description="Get time", parameters={}),
  ]
  let body = build_responses_api_body(
    test_model_openai_responses, messages, tools,
  )
  match body {
    { "model": String(model), "input": Array(_), "tools": Array(t), .. } => {
      assert_eq(model, test_model_openai_responses)
      inspect(t.length(), content="1")
    }
    _ => fail("Unexpected body format")
  }
}

///|
test "build_anthropic_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are Claude"),
    @types.ModelMessage::User(content="Hello", name=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_anthropic_body(
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
// Response Parser Tests
// =============================================================================

///|
test "parse_openai_chat_response parses text response" {
  let json : Json = {
    "choices": Json::array([
      {
        "message": { "role": "assistant", "content": "Hello!" },
        "finish_reason": "stop",
      },
    ]),
  }
  let response = parse_openai_chat_response(json)
  match response {
    @types.ModelResponse::Text(content) => inspect(content, content="Hello!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_openai_chat_response parses tool_calls response" {
  let json : Json = {
    "choices": Json::array([
      {
        "message": {
          "role": "assistant",
          "content": Json::null(),
          "tool_calls": Json::array([
            {
              "id": "call_abc",
              "type": "function",
              "function": {
                "name": "get_weather",
                "arguments": "{\"city\":\"Tokyo\"}",
              },
            },
          ]),
        },
        "finish_reason": "tool_calls",
      },
    ]),
  }
  let response = parse_openai_chat_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse_responses_api_response parses text response" {
  let json : Json = {
    "id": Json::string(test_response_id),
    "output": Json::array([
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([{ "type": "output_text", "text": "Hi there!" }]),
      },
    ]),
  }
  let response = parse_responses_api_response(json)
  match response {
    @types.ModelResponse::Text(content) => inspect(content, content="Hi there!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_anthropic_response parses text response" {
  let json : Json = {
    "content": Json::array([{ "type": "text", "text": "Hello from Claude!" }]),
    "stop_reason": "end_turn",
  }
  let response = parse_anthropic_response(json)
  match response {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello from Claude!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_anthropic_response parses tool_use response" {
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
  let response = parse_anthropic_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="search")
    }
    _ => fail("Expected ToolCalls response")
  }
}
