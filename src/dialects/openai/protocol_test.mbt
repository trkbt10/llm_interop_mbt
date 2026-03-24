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
  let msg = @types.ModelMessage::User(
    content="Hello",
    name=None,
    content_parts=None,
  )
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

///|
test "tool_to_responses_api_json preserves generic builtin config" {
  let tool = @types.ToolDefinition::builtin(type_="code_interpreter", config={
    "container": { "type": "auto" },
  })
  let json = tool_to_responses_api_json(tool)
  match json {
    { "type": "code_interpreter", "container": { "type": "auto", .. }, .. } =>
      ()
    _ => fail("Unexpected builtin tool format")
  }
}

///|
test "chat_completions_resolve extracts model from request body" {
  let body = "{\"model\":\"gpt-4.1-mini\",\"messages\":[]}"
  match chat_completions_resolve("POST", "/v1/chat/completions", body) {
    Some((model, resolved_body)) => {
      assert_eq(model, "gpt-4.1-mini")
      assert_eq(resolved_body, body)
    }
    None => fail("Expected chat completion route")
  }
}

///|
test "responses_api_resolve extracts model from request body" {
  let body = "{\"model\":\"gpt-4.1-mini\",\"input\":\"hi\"}"
  match responses_api_resolve("POST", "/v1/responses", body) {
    Some((model, resolved_body)) => {
      assert_eq(model, "gpt-4.1-mini")
      assert_eq(resolved_body, body)
    }
    None => fail("Expected responses route")
  }
}

///|
test "route resolvers reject requests without model" {
  assert_eq(
    chat_completions_resolve(
      "POST", "/v1/chat/completions", "{\"messages\":[]}",
    ),
    None,
  )
  assert_eq(
    responses_api_resolve("POST", "/v1/responses", "{\"input\":\"hi\"}"),
    None,
  )
}

///|
test "messages_to_responses_input preserves builtin assistant tool items" {
  let messages = [
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::builtin(
          id="mcp_req_123",
          type_="mcp_approval_request",
          payload={
            "id": "mcp_req_123",
            "server_label": "docs",
            "name": "lookup_docs",
            "arguments": "{\"topic\":\"MoonBit\"}",
          },
          name="lookup_docs",
        ),
      ]),
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    {
      "type": String("mcp_approval_request"),
      "id": String(id),
      "server_label": String(server_label),
      "name": String(name),
      ..
    } => {
      assert_eq(id, "mcp_req_123")
      assert_eq(server_label, "docs")
      assert_eq(name, "lookup_docs")
    }
    _ => fail("Expected builtin assistant tool item")
  }
}

///|
test "messages_to_responses_input re-emits wrapped builtin tool results" {
  let messages = [
    @types.ModelMessage::ToolResult(
      tool_call_id="mcp_req_123",
      content=(
        #|{"type":"mcp_approval_response","approve":true,"reason":"approved"}
      ),
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    {
      "type": String("mcp_approval_response"),
      "approval_request_id": String(id),
      "approve": True,
      "reason": String(reason),
      ..
    } => {
      assert_eq(id, "mcp_req_123")
      assert_eq(reason, "approved")
    }
    _ => fail("Expected raw builtin tool result item")
  }
}

///|
test "messages_to_responses_input restores builtin tool result identifier fields" {
  let messages = [
    @types.ModelMessage::ToolResult(
      tool_call_id="shell_item_123",
      content="{\"type\":\"local_shell_call_output\",\"output\":\"ok\"}",
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_456",
      content="{\"type\":\"apply_patch_call_output\",\"status\":\"completed\"}",
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    {
      "type": String("local_shell_call_output"),
      "id": String(id),
      "output": String(output),
      ..
    } => {
      assert_eq(id, "shell_item_123")
      assert_eq(output, "ok")
    }
    _ => fail("Expected local shell output item")
  }
  match input[1] {
    {
      "type": String("apply_patch_call_output"),
      "call_id": String(id),
      "status": String(status),
      ..
    } => {
      assert_eq(id, "call_456")
      assert_eq(status, "completed")
    }
    _ => fail("Expected apply patch output item")
  }
}

///|
test "messages_to_responses_input restores identifiers across builtin output item families" {
  let messages = [
    @types.ModelMessage::ToolResult(
      tool_call_id="computer_item_123",
      content="{\"type\":\"computer_call_output\",\"output\":{\"ack\":true}}",
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="shell_call_456",
      content="{\"type\":\"shell_call_output\",\"output\":\"ok\"}",
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    {
      "type": String("computer_call_output"),
      "id": String(id),
      "output": { "ack": True, .. },
      ..
    } => assert_eq(id, "computer_item_123")
    _ => fail("Expected computer_call_output item")
  }
  match input[1] {
    {
      "type": String("shell_call_output"),
      "call_id": String(id),
      "output": String(output),
      ..
    } => {
      assert_eq(id, "shell_call_456")
      assert_eq(output, "ok")
    }
    _ => fail("Expected shell_call_output item")
  }
}

// =============================================================================
// Request Body Builder Tests (OpenAI Format)
// =============================================================================

///|
test "build_chat_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are helpful"),
    @types.ModelMessage::User(content="Hello", name=None, content_parts=None),
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
test "build_chat_body normalizes strict json_schema response format" {
  let body = build_chat_body(
    test_model_openai,
    [@types.ModelMessage::User(content="Hello", name=None, content_parts=None)],
    [],
    response_format=Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=None,
        strict=Some(true),
      ),
    ),
  )
  match body {
    { "response_format": { "json_schema": { "schema": schema, .. }, .. }, .. } =>
      assert_false(schema_needs_normalization(schema))
    _ => fail("Expected normalized chat response_format")
  }
}

///|
test "build_responses_api_body creates valid body" {
  let messages = [
    @types.ModelMessage::User(
      content="What time is it?",
      name=None,
      content_parts=None,
    ),
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
test "build_responses_api_body sets nested text.format for structured output" {
  let body = build_responses_api_body(
    test_model_openai_responses,
    [
      @types.ModelMessage::User(
        content="Return JSON",
        name=None,
        content_parts=None,
      ),
    ],
    [],
    response_format=Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=None,
        strict=Some(true),
      ),
    ),
  )
  match body {
    { "text": { "format": { "schema": schema, .. }, .. }, .. } =>
      assert_false(schema_needs_normalization(schema))
    _ => fail("Expected nested Responses text.format")
  }
}

///|
test "build_responses_api_body includes web search builtin tool" {
  let messages = [
    @types.ModelMessage::User(
      content="What's new?",
      name=None,
      content_parts=None,
    ),
  ]
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
test "parse_chat_response preserves mixed text and tool_calls" {
  let json : Json = {
    "choices": Json::array([
      {
        "message": {
          "role": "assistant",
          "content": "Let me check",
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
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "get_weather")
      assert_eq(rich.content, "Let me check")
    }
    _ => fail("Expected ToolCallsWithContent response")
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
        _ => fail("Expected URL citation")
      }
      assert_eq(rich.tool_traces[0].id, "ws_001")
      assert_eq(rich.tool_traces[0].kind, @types.ToolCallKind::WebSearch)
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_responses_api_response preserves interop citation extensions" {
  let json : Json = {
    "output": Json::array([
      {
        "type": "message",
        "content": Json::array([
          {
            "type": "output_text",
            "text": "Berkshire Hathaway",
            "annotations": Json::array([
              {
                "type": "web_search_result_location",
                "cited_text": "Berkshire Hathaway",
                "encrypted_index": "enc_berkshire",
                "title": "Berkshire Hathaway",
                "url": "https://example.com/berkshire",
                "start_index": 0,
                "end_index": 18,
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
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::WebSearchResultCitation(
          encrypted_index~,
          title~,
          url~,
          start_index~,
          end_index~,
          ..
        ) => {
          assert_eq(encrypted_index, "enc_berkshire")
          assert_eq(title, "Berkshire Hathaway")
          assert_eq(url, "https://example.com/berkshire")
          assert_eq(start_index, 0)
          assert_eq(end_index, 18)
        }
        _ => fail("Expected web search result citation")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_responses_api_response preserves builtin hosted tool traces" {
  let json : Json = {
    "output": Json::array([
      {
        "type": "file_search_call",
        "id": "fs_001",
        "status": "completed",
        "results": Json::array([
          { "file_id": "file_123", "filename": "docs.md", "score": 0.98 },
        ]),
      },
      {
        "type": "message",
        "content": Json::array([
          { "type": "output_text", "text": "Found relevant docs." },
        ]),
      },
    ]),
  }
  let response = parse_responses_api_response(json)
  match response {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.tool_traces.length(), 1)
      assert_eq(
        rich.tool_traces[0].kind,
        @types.ToolCallKind::Builtin(builtin_type="file_search_call"),
      )
      match rich.tool_traces[0].arguments {
        { "results": Array(results), .. } => assert_eq(results.length(), 1)
        _ => fail("Expected stored builtin payload")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_responses_api_response returns ToolCalls for actionable builtin items" {
  let json : Json = {
    "output": Json::array([
      {
        "type": "mcp_call",
        "id": "mcp_001",
        "name": "lookup_docs",
        "server_label": "docs",
        "arguments": "{\"topic\":\"MoonBit\"}",
        "status": "completed",
        "output": "Found docs",
      },
    ]),
  }
  let response = parse_responses_api_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(
        calls[0].kind,
        @types.ToolCallKind::Builtin(builtin_type="mcp_call"),
      )
      assert_eq(calls[0].name, "lookup_docs")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "message_to_json converts User with content_parts (multimodal)" {
  let msg = @types.ModelMessage::User(
    content="What is this?",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("What is this?"),
      @types.ContentPart::ImageUrl(
        url="https://example.com/cat.png",
        detail=Some("auto"),
      ),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } => {
      inspect(parts.length(), content="2")
      match parts[0] {
        { "type": "text", "text": "What is this?", .. } => ()
        _ => fail("Expected text part")
      }
      match parts[1] {
        { "type": "image_url", "image_url": { "url": String(url), .. }, .. } =>
          inspect(url, content="https://example.com/cat.png")
        _ => fail("Expected image_url part")
      }
    }
    _ => fail("Expected array content")
  }
}

///|
test "message_to_json converts User with base64 image" {
  let msg = @types.ModelMessage::User(
    content="Describe",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Describe"),
      @types.ContentPart::ImageBase64(data="abc123", media_type="image/png"),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        { "type": "image_url", "image_url": { "url": String(url), .. }, .. } =>
          assert_true(url.has_prefix("data:image/png;base64,"))
        _ => fail("Expected image_url with data URL")
      }
    _ => fail("Expected array content")
  }
}

///|
test "messages_to_responses_input handles multimodal User" {
  let messages = [
    @types.ModelMessage::User(
      content="Look at this",
      name=None,
      content_parts=Some([
        @types.ContentPart::Text("Look at this"),
        @types.ContentPart::ImageUrl(
          url="https://example.com/img.jpg",
          detail=None,
        ),
      ]),
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    { "role": "user", "content": Array(blocks), .. } => {
      inspect(blocks.length(), content="2")
      match blocks[0] {
        { "type": "input_text", "text": "Look at this", .. } => ()
        _ => fail("Expected input_text block")
      }
      match blocks[1] {
        { "type": "input_image", "image_url": String(url), .. } =>
          inspect(url, content="https://example.com/img.jpg")
        _ => fail("Expected input_image block")
      }
    }
    _ => fail("Expected user with array content")
  }
}

///|
test "parse_responses_api_response handles output_image" {
  let response : Json = {
    "output": Json::array([
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([
          { "type": "output_text", "text": "Here is the image:" },
          {
            "type": "output_image",
            "image_url": "https://example.com/generated.png",
          },
        ]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="Here is the image:")
      match rich.content_parts {
        Some(parts) => {
          inspect(parts.length(), content="2")
          match parts[1] {
            @types.ResponseContentPart::OutputImage(url~) =>
              inspect(url, content="https://example.com/generated.png")
            _ => fail("Expected OutputImage part")
          }
        }
        None => fail("Expected content_parts")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_responses_api_response preserves output_text boundaries in mixed content" {
  let response : Json = {
    "output": Json::array([
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([
          { "type": "output_text", "text": "before", "annotations": [] },
          {
            "type": "output_image",
            "image_url": "https://example.com/generated.png",
          },
          { "type": "output_text", "text": "after", "annotations": [] },
        ]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "beforeafter")
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 3)
          match parts[0] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "before")
            _ => fail("Expected leading OutputText")
          }
          match parts[1] {
            @types.ResponseContentPart::OutputImage(url~) =>
              assert_eq(url, "https://example.com/generated.png")
            _ => fail("Expected OutputImage")
          }
          match parts[2] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "after")
            _ => fail("Expected trailing OutputText")
          }
        }
        None => fail("Expected content_parts")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_responses_api_response handles refusal" {
  let response : Json = {
    "output": Json::array([
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([
          { "type": "refusal", "refusal": "I cannot help with that." },
        ]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          match parts[0] {
            @types.ResponseContentPart::Refusal(reason) =>
              inspect(reason, content="I cannot help with that.")
            _ => fail("Expected Refusal part")
          }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_chat_response handles refusal" {
  let response : Json = {
    "choices": Json::array([
      {
        "message": {
          "role": "assistant",
          "content": Json::null(),
          "refusal": "I cannot help with that request.",
        },
        "finish_reason": "stop",
      },
    ]),
  }
  let result = parse_chat_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          match parts[0] {
            @types.ResponseContentPart::Refusal(reason) =>
              inspect(reason, content="I cannot help with that request.")
            _ => fail("Expected Refusal part")
          }
        None => fail("Expected content_parts for refusal")
      }
    _ => fail("Expected RichText response for refusal")
  }
}

///|
test "parse_responses_api_response handles reasoning output" {
  let response : Json = {
    "output": Json::array([
      {
        "type": "reasoning",
        "content": Json::array([
          { "type": "text", "text": "Step 1: analyze..." },
        ]),
      },
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([
          { "type": "output_text", "text": "The answer is 42." },
        ]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="The answer is 42.")
      match rich.content_parts {
        Some(parts) => {
          let mut has_thinking = false
          let mut has_text = false
          for part in parts {
            match part {
              @types.ResponseContentPart::Thinking(..) => has_thinking = true
              @types.ResponseContentPart::OutputText(_) => has_text = true
              _ => ()
            }
          }
          inspect(has_thinking, content="true")
          inspect(has_text, content="true")
        }
        None => fail("Expected content_parts for reasoning")
      }
    }
    _ => fail("Expected RichText response for reasoning")
  }
}

///|
test "message_to_json converts User with audio content_parts" {
  let msg = @types.ModelMessage::User(
    content="Transcribe this",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Transcribe this"),
      @types.ContentPart::Audio(data="base64audio", format="wav"),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } => {
      inspect(parts.length(), content="2")
      match parts[1] {
        {
          "type": "input_audio",
          "input_audio": { "data": "base64audio", "format": "wav", .. },
          ..
        } => ()
        _ => fail("Expected input_audio part")
      }
    }
    _ => fail("Expected array content")
  }
}

///|
test "reasoning item roundtrip: generate then parse" {
  // Generate a reasoning item via build_responses_reasoning_item
  let reasoning_json = build_responses_reasoning_item("Step 1: analyze...")
  // Wrap in a full response with a message
  let response : Json = {
    "output": Json::array([
      reasoning_json,
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([
          { "type": "output_text", "text": "The answer is 42." },
        ]),
      },
    ]),
  }
  // Parse it back
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="The answer is 42.")
      match rich.content_parts {
        Some(parts) => {
          // Should have Thinking (from summary_text) + OutputText
          let mut thinking_found = false
          for p in parts {
            match p {
              @types.ResponseContentPart::Thinking(text~) => {
                inspect(text, content="Step 1: analyze...")
                thinking_found = true
              }
              _ => ()
            }
          }
          assert_true(thinking_found)
        }
        None => fail("Expected content_parts with reasoning")
      }
    }
    _ => fail("Expected RichText")
  }
}

///|
test "parse_responses_api_response reads reasoning_text from content array" {
  let response : Json = {
    "output": Json::array([
      {
        "type": "reasoning",
        "content": Json::array([
          { "type": "reasoning_text", "text": "Detailed reasoning here" },
        ]),
        "summary": Json::array([{ "type": "summary_text", "text": "Summary" }]),
      },
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([{ "type": "output_text", "text": "Done." }]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          // Should prefer content (reasoning_text) over summary
          let mut found_detailed = false
          for p in parts {
            match p {
              @types.ResponseContentPart::Thinking(text~) =>
                if text == "Detailed reasoning here" {
                  found_detailed = true
                }
              _ => ()
            }
          }
          assert_true(found_detailed)
        }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "reasoning item roundtrip preserves encrypted_content" {
  let reasoning_json = build_responses_reasoning_item(
    "",
    encrypted_content=Some("enc_blob"),
  )
  let response : Json = {
    "output": Json::array([
      reasoning_json,
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array([{ "type": "output_text", "text": "Done." }]),
      },
    ]),
  }
  let result = parse_responses_api_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          let mut found = false
          for part in parts {
            match part {
              @types.ResponseContentPart::RedactedThinking(data~) =>
                if data == "enc_blob" {
                  found = true
                }
              _ => ()
            }
          }
          assert_true(found)
        }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "model_response_to_responses_json preserves builtin hosted tool traces" {
  let response = @types.ModelResponse::RichText(
    @types.RichTextResponse::new(content="Found relevant docs.", tool_traces=[
      @types.ToolCallTrace::new(
        id="fs_001",
        name="file_search_call",
        kind=@types.ToolCallKind::Builtin(builtin_type="file_search_call"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={
          "type": "file_search_call",
          "id": "fs_001",
          "status": "completed",
          "results": Json::array([
            { "file_id": "file_123", "filename": "docs.md", "score": 0.98 },
          ]),
        },
      ),
    ]),
  )
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model_openai_responses,
  )
  match json {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 2)
      match output[0] {
        { "type": String("file_search_call"), "results": Array(results), .. } =>
          assert_eq(results.length(), 1)
        _ => fail("Expected builtin hosted tool output")
      }
    }
    _ => fail("Expected response JSON")
  }
}

///|
test "model_response_to_responses_json preserves hosted builtin trace subtypes" {
  let response = @types.ModelResponse::RichText(
    @types.RichTextResponse::new(content="Hosted tools finished.", tool_traces=[
      @types.ToolCallTrace::new(
        id="ts_001",
        name="tool_search_output",
        kind=@types.ToolCallKind::Builtin(builtin_type="tool_search_output"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={
          "type": "tool_search_output",
          "id": "ts_001",
          "status": "completed",
          "results": Json::array([{ "tool": "docs_lookup" }]),
        },
      ),
      @types.ToolCallTrace::new(
        id="img_001",
        name="image_generation_call",
        kind=@types.ToolCallKind::Builtin(builtin_type="image_generation_call"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={
          "type": "image_generation_call",
          "id": "img_001",
          "status": "completed",
          "result": "https://example.com/generated.png",
        },
      ),
      @types.ToolCallTrace::new(
        id="ci_001",
        name="code_interpreter_call",
        kind=@types.ToolCallKind::Builtin(builtin_type="code_interpreter_call"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={
          "type": "code_interpreter_call",
          "id": "ci_001",
          "status": "completed",
          "code": "print(1)",
        },
      ),
      @types.ToolCallTrace::new(
        id="mcp_list_001",
        name="mcp_list_tools",
        kind=@types.ToolCallKind::Builtin(builtin_type="mcp_list_tools"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={
          "type": "mcp_list_tools",
          "id": "mcp_list_001",
          "server_label": "docs",
          "tools": Json::array([{ "name": "lookup_docs" }]),
        },
      ),
    ]),
  )
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model_openai_responses,
  )
  match json {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 5)
      match output[0] {
        { "type": String("tool_search_output"), "results": Array(results), .. } =>
          assert_eq(results.length(), 1)
        _ => fail("Expected tool_search_output")
      }
      match output[1] {
        { "type": String("image_generation_call"), "result": String(url), .. } =>
          assert_eq(url, "https://example.com/generated.png")
        _ => fail("Expected image_generation_call")
      }
      match output[2] {
        { "type": String("code_interpreter_call"), "code": String(code), .. } =>
          assert_eq(code, "print(1)")
        _ => fail("Expected code_interpreter_call")
      }
      match output[3] {
        {
          "type": String("mcp_list_tools"),
          "server_label": String(label),
          "tools": Array(tools),
          ..
        } => {
          assert_eq(label, "docs")
          assert_eq(tools.length(), 1)
        }
        _ => fail("Expected mcp_list_tools")
      }
      match output[4] {
        { "type": String("message"), .. } => ()
        _ => fail("Expected trailing message output")
      }
    }
    _ => fail("Expected response JSON")
  }
}

///|
test "messages_to_responses_input handles document via input_file" {
  let messages = [
    @types.ModelMessage::User(
      content="Read this PDF",
      name=None,
      content_parts=Some([
        @types.ContentPart::Text("Read this PDF"),
        @types.ContentPart::Document(
          data="base64pdf",
          media_type="application/pdf",
          title=Some("report.pdf"),
        ),
      ]),
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    { "role": "user", "content": Array(blocks), .. } =>
      match blocks[1] {
        {
          "type": "input_file",
          "file_data": String(data_url),
          "filename": "report.pdf",
          ..
        } => assert_true(data_url.has_prefix("data:application/pdf;base64,"))
        _ => fail("Expected input_file with file_data")
      }
    _ => fail("Expected user with array content")
  }
}

///|
test "messages_to_responses_input handles remote file url via input_file" {
  let messages = [
    @types.ModelMessage::User(
      content="Read this remote file",
      name=None,
      content_parts=Some([
        @types.ContentPart::Text("Read this remote file"),
        @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
      ]),
    ),
  ]
  let input = messages_to_responses_input(messages)
  match input[0] {
    { "role": "user", "content": Array(blocks), .. } =>
      match blocks[1] {
        { "type": "input_file", "file_url": String(url), .. } =>
          assert_eq(url, "https://example.com/report.pdf")
        _ => fail("Expected input_file with file_url")
      }
    _ => fail("Expected user with array content")
  }
}

///|
test "Chat Completions document renders as file content part" {
  let msg = @types.ModelMessage::User(
    content="Read this",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Read this"),
      @types.ContentPart::Document(
        data="base64pdf",
        media_type="application/pdf",
        title=Some("report.pdf"),
      ),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        {
          "type": "file",
          "file": { "file_data": String(data), "filename": String(name), .. },
          ..
        } => {
          assert_eq(data, "data:application/pdf;base64,base64pdf")
          assert_eq(name, "report.pdf")
        }
        _ => fail("Expected file content part for PDF in Chat Completions")
      }
    _ => fail("Expected array content")
  }
}

///|
test "Chat Completions text/plain document uses file_data" {
  let msg = @types.ModelMessage::User(
    content="Read this",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Read this"),
      @types.ContentPart::Document(
        data="SGVsbG8gV29ybGQ=",
        media_type="text/plain",
        title=Some("readme.txt"),
      ),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        {
          "type": "file",
          "file": { "file_data": String(data), "filename": String(name), .. },
          ..
        } => {
          assert_eq(data, "data:text/plain;base64,SGVsbG8gV29ybGQ=")
          assert_eq(name, "readme.txt")
        }
        _ => fail("Expected file content part")
      }
    _ => fail("Expected array content")
  }
}

///|
test "Chat Completions file ref uses file_id content part" {
  let msg = @types.ModelMessage::User(
    content="Read this file",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Read this file"),
      @types.ContentPart::FileRef(file_id="file_123", media_type=None),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        { "type": "file", "file": { "file_id": String(id), .. }, .. } =>
          assert_eq(id, "file_123")
        _ => fail("Expected file_id content part")
      }
    _ => fail("Expected array content")
  }
}

///|
test "Chat Completions file url falls back to text part" {
  let msg = @types.ModelMessage::User(
    content="Read this file",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Read this file"),
      @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        { "type": "text", "text": String(text), .. } => {
          assert_true(text.contains("Remote file URL input"))
          assert_true(text.contains("https://example.com/report.pdf"))
        }
        _ => fail("Expected text fallback content part")
      }
    _ => fail("Expected array content")
  }
}
