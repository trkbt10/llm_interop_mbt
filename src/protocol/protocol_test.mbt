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
test "tool_to_responses_api_json creates web search builtin format" {
  let tool = @types.ToolDefinition::web_search_preview(
    search_context_size=Some("medium"),
    user_location_country=Some("US"),
  )
  let json = tool_to_responses_api_json(tool)
  match json {
    {
      "type": "web_search_preview",
      "search_context_size": "medium",
      "user_location": { "type": "approximate", "country": "US", .. },
      ..
    } => ()
    _ => fail("Unexpected web search tool format")
  }
}

///|
test "parse_responses_api_response preserves annotations and web search traces" {
  let json : Json = {
    "output": Json::array([
      {
        "id": "ws_001",
        "type": "web_search_call",
        "status": "completed",
        "action": {
          "type": "search",
          "query": "current weather in Tokyo",
          "queries": Json::array([Json::string("current weather in Tokyo")]),
        },
      },
      {
        "type": "message",
        "content": Json::array([
          {
            "type": "output_text",
            "text": "Weather details",
            "annotations": Json::array([
              {
                "type": "url_citation",
                "url": "https://example.com/weather",
                "title": "Weather Source",
                "start_index": 0,
                "end_index": 7,
              },
            ]),
          },
        ]),
      },
    ]),
  }
  let response = parse_responses_api_response(json)
  match response {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      assert_eq(rich.tool_traces.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::UrlCitation(url~, ..) =>
          assert_eq(url, "https://example.com/weather")
      }
      assert_eq(rich.tool_traces[0].id, "ws_001")
      assert_eq(rich.tool_traces[0].kind, @types.ToolCallKind::WebSearch)
    }
    _ => fail("Expected RichText response")
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
test "build_responses_api_body includes web search builtin tool" {
  let messages = [@types.ModelMessage::User(content="What's new?", name=None)]
  let tools = [
    @types.ToolDefinition::web_search_preview_2025_03_11(
      search_context_size=Some("medium"),
      user_location_country=Some("US"),
    ),
  ]
  let body = build_responses_api_body(
    test_model_openai_responses, messages, tools,
  )
  match body {
    { "tools": Array(tool_defs), "tool_choice": String(choice), .. } => {
      assert_eq(choice, "auto")
      match tool_defs[0] {
        { "type": String("web_search_preview_2025_03_11"), .. } => ()
        _ => fail("Expected versioned web search tool")
      }
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

// =============================================================================
// Gemini Protocol Tests
// =============================================================================

///|
test "message_to_gemini_content converts User message" {
  let msg = @types.ModelMessage::User(content="Hello Gemini", name=None)
  match message_to_gemini_content(msg) {
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
test "message_to_gemini_content converts Assistant with tool_calls" {
  let calls = [
    @types.ToolCallRequest::new(id="gemini_search_0", name="search", arguments={
      "query": "MoonBit",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  match message_to_gemini_content(msg) {
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
test "gemini_content_to_json converts text content" {
  let content : GeminiContent = {
    role: "user",
    parts: [GeminiPart::Text("Hello")],
  }
  let json = gemini_content_to_json(content)
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
test "gemini_content_to_json converts function call" {
  let content : GeminiContent = {
    role: "model",
    parts: [
      GeminiPart::FunctionCall(name="get_weather", args={ "city": "Tokyo" }),
    ],
  }
  let json = gemini_content_to_json(content)
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
test "tool_to_gemini_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="calculator",
    description="Calculate math expressions",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_gemini_json(tool)
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
test "tools_to_gemini_json wraps in functionDeclarations" {
  let tools = [
    @types.ToolDefinition::new(name="tool1", description="First tool", parameters={}),
    @types.ToolDefinition::new(name="tool2", description="Second tool", parameters={}),
  ]
  let json = tools_to_gemini_json(tools)
  match json {
    { "functionDeclarations": Array(decls), .. } =>
      inspect(decls.length(), content="2")
    _ => fail("Expected functionDeclarations array")
  }
}

///|
test "build_gemini_body creates valid body" {
  let messages = [@types.ModelMessage::User(content="Calculate 2+2", name=None)]
  let tools = [
    @types.ToolDefinition::new(name="calculator", description="Math", parameters={}),
  ]
  let body = build_gemini_body(
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
test "parse_gemini_response parses text response" {
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
  let response = parse_gemini_response(json)
  match response {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="The answer is 4")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_gemini_response parses function call response" {
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
  let response = parse_gemini_response(json)
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
test "parse_gemini_response handles safety block" {
  let json : Json = {
    "candidates": Json::array([{ "finishReason": "SAFETY" }]),
  }
  let response = parse_gemini_response(json)
  match response {
    @types.ModelResponse::ModelError(msg) => assert_true(msg.contains("safety"))
    _ => fail("Expected ModelError response")
  }
}
