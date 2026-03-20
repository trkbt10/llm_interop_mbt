///|
/// Gemini dialect protocol tests

// =============================================================================
// Message Conversion Tests (Gemini Format)
// =============================================================================

///|
test "message_to_content converts User message" {
  let msg = @types.ModelMessage::User(content="Hello Gemini", name=None)
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.role, content="user")
      inspect(content.parts.length(), content="1")
      match content.parts[0] {
        GeminiPart::Text(t) => inspect(t, content="Hello Gemini")
        _ => fail("Expected Text part")
      }
    }
    None => fail("Expected Some content")
  }
}

///|
test "message_to_content converts Assistant with tool_calls" {
  let calls = [
    @types.ToolCallRequest::new(id="gemini_search_0", name="search", arguments={
      "query": "MoonBit",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.role, content="model")
      inspect(content.parts.length(), content="1")
      match content.parts[0] {
        GeminiPart::FunctionCall(name~, ..) => inspect(name, content="search")
        _ => fail("Expected FunctionCall part")
      }
    }
    None => fail("Expected Some content")
  }
}

///|
test "content_to_json converts text content" {
  let content : GeminiContent = {
    role: "user",
    parts: [GeminiPart::Text("Hello")],
  }
  let json = content_to_json(content)
  match json {
    { "role": "user", "parts": Array(parts), .. } => {
      inspect(parts.length(), content="1")
      match parts[0] {
        { "text": "Hello", .. } => ()
        _ => fail("Expected text part")
      }
    }
    _ => fail("Unexpected JSON format")
  }
}

///|
test "content_to_json converts function call" {
  let content : GeminiContent = {
    role: "model",
    parts: [
      GeminiPart::FunctionCall(name="get_weather", args={ "city": "Tokyo" }),
    ],
  }
  let json = content_to_json(content)
  match json {
    { "role": "model", "parts": Array(parts), .. } =>
      match parts[0] {
        {
          "functionCall": {
            "name": "get_weather",
            "args": { "city": "Tokyo", .. },
            ..
          },
          ..
        } => ()
        _ => fail("Expected functionCall part")
      }
    _ => fail("Unexpected JSON format")
  }
}

///|
test "tool_to_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="calculator",
    description="Calculate math expressions",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_json(tool)
  match json {
    {
      "name": "calculator",
      "description": "Calculate math expressions",
      "parameters": _,
      ..
    } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "tools_to_json wraps in functionDeclarations" {
  let tools = [
    @types.ToolDefinition::new(name="tool1", description="First tool", parameters={}),
    @types.ToolDefinition::new(name="tool2", description="Second tool", parameters={}),
  ]
  let json = tools_to_json(tools)
  match json {
    { "functionDeclarations": Array(decls), .. } =>
      inspect(decls.length(), content="2")
    _ => fail("Expected functionDeclarations array")
  }
}

///|
test "build_body creates valid body" {
  let messages = [@types.ModelMessage::User(content="Calculate 2+2", name=None)]
  let tools = [
    @types.ToolDefinition::new(name="calculator", description="Math", parameters={}),
  ]
  let body = build_body(
    messages,
    tools,
    max_tokens=Some(1000),
    temperature=Some(0.7),
  )
  match body {
    {
      "contents": Array(contents),
      "tools": Array(tools_arr),
      "generationConfig": {
        "maxOutputTokens": Number(mt, ..),
        "temperature": Number(temp, ..),
        ..
      },
      ..
    } => {
      inspect(contents.length(), content="1")
      inspect(tools_arr.length(), content="1")
      inspect(mt, content="1000")
      inspect(temp, content="0.7")
    }
    _ => fail("Unexpected body format")
  }
}

///|
test "parse_response parses text response" {
  let json : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([{ "text": "The answer is 4" }]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="The answer is 4")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_response parses function call response" {
  let json : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            {
              "functionCall": {
                "name": "get_weather",
                "args": { "city": "Tokyo" },
              },
            },
          ]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      // ID is generated since Gemini doesn't provide IDs
      assert_true(calls[0].id.has_prefix("gemini_"))
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse_response handles safety block" {
  let json : Json = {
    "candidates": Json::array([{ "finishReason": "SAFETY" }]),
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::ModelError(msg) => assert_true(msg.contains("safety"))
    _ => fail("Expected ModelError response")
  }
}
