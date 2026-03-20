///|
/// OpenAI dialect protocol tests

// Test fixtures
let test_model_openai : String = "gpt-4"

///|
let test_model_openai_responses : String = "gpt-4o"

///|
let test_response_id : String = "resp_123"

// =============================================================================
// Message Conversion Tests (OpenAI Format)
// =============================================================================

///|
test "message_to_json converts System message" {
  let msg = @types.ModelMessage::System("You are a helpful assistant")
  let json = message_to_json(msg)
  match json {
    { "role": "system", "content": "You are a helpful assistant", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_json converts User message" {
  let msg = @types.ModelMessage::User(content="Hello", name=None)
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": "Hello", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_json converts Assistant with tool_calls" {
  let calls = [
    @types.ToolCallRequest::new(id="call_123", name="get_weather", arguments={
      "city": "Tokyo",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  let json = message_to_json(msg)
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
test "message_to_json converts ToolResult" {
  let msg = @types.ModelMessage::ToolResult(
    tool_call_id="call_123",
    content="Sunny, 25C",
  )
  let json = message_to_json(msg)
  match json {
    { "role": "tool", "tool_call_id": "call_123", "content": "Sunny, 25C", .. } =>
      ()
    _ => fail("Unexpected JSON format")
  }
}

// =============================================================================
// Tool Conversion Tests (OpenAI Format)
// =============================================================================

///|
test "tool_to_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="get_weather",
    description="Get weather info",
    parameters={
      "type": "object",
      "properties": { "city": { "type": "string" } },
    },
  )
  let json = tool_to_json(tool)
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

// =============================================================================
// Request Body Builder Tests (OpenAI Format)
// =============================================================================

///|
test "build_chat_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are helpful"),
    @types.ModelMessage::User(content="Hello", name=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_chat_body(
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

// =============================================================================
// Response Parser Tests (OpenAI Format)
// =============================================================================

///|
test "parse_chat_response parses text response" {
  let json : Json = {
    "choices": Json::array([
      {
        "message": { "role": "assistant", "content": "Hello!" },
        "finish_reason": "stop",
      },
    ]),
  }
  let response = parse_chat_response(json)
  match response {
    @types.ModelResponse::Text(content) => inspect(content, content="Hello!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_chat_response parses tool_calls response" {
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
  let response = parse_chat_response(json)
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
