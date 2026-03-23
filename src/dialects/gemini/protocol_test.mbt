///|
/// Gemini dialect protocol tests

// =============================================================================
// Message Conversion Tests (Gemini Format)
// =============================================================================

///|
test "message_to_content converts User message" {
  let msg = @types.ModelMessage::User(
    content="Hello Gemini",
    name=None,
    content_parts=None,
  )
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
test "message_to_content converts ImageUrl to text placeholder" {
  let msg = @types.ModelMessage::User(
    content="",
    name=None,
    content_parts=Some([
      @types.ContentPart::ImageUrl(
        url="https://example.com/cat.png",
        detail=None,
      ),
    ]),
  )
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.role, content="user")
      inspect(content.parts.length(), content="1")
      match content.parts[0] {
        GeminiPart::Text(text) =>
          inspect(text, content="[Image: https://example.com/cat.png]")
        _ => fail("Expected Text placeholder")
      }
    }
    None => fail("Expected Some content")
  }
}

///|
test "message_to_content converts FileUrl to text placeholder" {
  let msg = @types.ModelMessage::User(
    content="",
    name=None,
    content_parts=Some([
      @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
    ]),
  )
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.role, content="user")
      inspect(content.parts.length(), content="1")
      match content.parts[0] {
        GeminiPart::Text(text) =>
          inspect(text, content="[File: https://example.com/report.pdf]")
        _ => fail("Expected Text placeholder")
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
test "tools_to_json includes codeExecution builtin" {
  let tools = [
    @types.ToolDefinition::new(name="tool1", description="First tool", parameters={}),
    @types.ToolDefinition::builtin(type_="codeExecution"),
  ]
  let json = tools_to_json(tools)
  match json {
    { "functionDeclarations": Array(decls), "codeExecution": Object(_), .. } =>
      inspect(decls.length(), content="1")
    _ => fail("Expected mixed Gemini tool object")
  }
}

///|
test "tools_to_json includes native Gemini builtin tools" {
  let tools = [
    @types.ToolDefinition::builtin(type_="googleSearch"),
    @types.ToolDefinition::builtin(type_="fileSearch", config={
      "fileSearchStoreNames": Json::array([
        Json::string("fileSearchStores/docs-123"),
      ]),
    }),
    @types.ToolDefinition::builtin(type_="urlContext"),
  ]
  let json = tools_to_json(tools)
  match json {
    {
      "googleSearch": Object(_),
      "fileSearch": { "fileSearchStoreNames": Array(stores), .. },
      "urlContext": Object(_),
      ..
    } => assert_eq(stores.length(), 1)
    _ => fail("Expected native Gemini builtin tools")
  }
}

///|
test "build_body creates valid body" {
  let messages = [
    @types.ModelMessage::User(
      content="Calculate 2+2",
      name=None,
      content_parts=None,
    ),
  ]
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
test "build_body lifts system messages into systemInstruction" {
  let messages = [
    @types.ModelMessage::System("You are a cat."),
    @types.ModelMessage::User(content="Say hi", name=None, content_parts=None),
  ]
  let body = build_body(messages, [])
  match body {
    {
      "contents": Array(contents),
      "systemInstruction": { "role": "user", "parts": Array(parts), .. },
      ..
    } => {
      inspect(contents.length(), content="1")
      match parts[0] {
        { "text": "You are a cat.", .. } => ()
        _ => fail("Expected systemInstruction text part")
      }
    }
    _ => fail("Expected systemInstruction in request body")
  }
}

///|
test "build_body emits responseJsonSchema for structured output" {
  let body = build_body(
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
        name=None,
        schema={ "type": "object", "required": ["answer"] },
        description=None,
        strict=None,
      ),
    ),
  )
  match body {
    {
      "generationConfig": {
        "responseMimeType": "application/json",
        "responseJsonSchema": { "type": "object", .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Gemini responseJsonSchema")
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
test "parse_response separates Gemini thought summaries from answer text" {
  let json : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            {
              "text": "I should check the arithmetic carefully.",
              "thought": true,
              "thoughtSignature": "sig_123",
            },
            { "text": "The answer is 4." },
          ]),
        },
        "finishReason": "STOP",
      },
    ]),
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "The answer is 4.")
      match rich.content_parts {
        Some(parts) => {
          let mut found_thinking = false
          let mut found_signature = false
          let mut found_answer = false
          for part in parts {
            match part {
              @types.ResponseContentPart::Thinking(text~) =>
                if text == "I should check the arithmetic carefully." {
                  found_thinking = true
                }
              @types.ResponseContentPart::RedactedThinking(data~) =>
                if data == "sig_123" {
                  found_signature = true
                }
              @types.ResponseContentPart::OutputText(text) =>
                if text == "The answer is 4." {
                  found_answer = true
                }
              _ => ()
            }
          }
          assert_true(found_thinking)
          assert_true(found_signature)
          assert_true(found_answer)
        }
        None => fail("Expected structured content parts")
      }
    }
    _ => fail("Expected RichText response")
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
test "parse_response preserves mixed text and function call" {
  let json : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            { "text": "Checking..." },
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
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "get_weather")
      assert_eq(rich.content, "Checking...")
    }
    _ => fail("Expected ToolCallsWithContent response")
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

///|
test "parse_response handles code execution output" {
  let response : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            { "text": "Let me calculate that." },
            {
              "executableCode": { "language": "python", "code": "print(2 + 2)" },
            },
            {
              "codeExecutionResult": {
                "outcome": "OUTCOME_OK",
                "output": "4\n",
              },
            },
            { "text": "The answer is 4." },
          ]),
        },
      },
    ]),
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(
        rich.content.contains("Let me calculate") &&
        rich.content.contains("answer is 4"),
        content="true",
      )
      match rich.content_parts {
        Some(parts) => {
          inspect(parts.length(), content="4")
          match parts[1] {
            @types.ResponseContentPart::CodeExecution(language~, code~) => {
              inspect(language, content="python")
              inspect(code, content="print(2 + 2)")
            }
            _ => fail("Expected CodeExecution")
          }
          match parts[2] {
            @types.ResponseContentPart::CodeResult(outcome~, output~) => {
              inspect(outcome, content="OUTCOME_OK")
              inspect(output, content="4\n")
            }
            _ => fail("Expected CodeResult")
          }
        }
        None => fail("Expected content_parts")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "message_to_content handles audio content_parts" {
  let msg = @types.ModelMessage::User(
    content="Transcribe this audio",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Transcribe this audio"),
      @types.ContentPart::Audio(data="base64audio", format="wav"),
    ]),
  )
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.parts.length(), content="2")
      match content.parts[1] {
        GeminiPart::InlineData(mime_type~, data~) => {
          inspect(mime_type, content="audio/wav")
          inspect(data, content="base64audio")
        }
        _ => fail("Expected InlineData for audio")
      }
    }
    None => fail("Expected content")
  }
}

///|
test "message_to_content handles document content_parts" {
  let msg = @types.ModelMessage::User(
    content="Summarize this PDF",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Summarize this PDF"),
      @types.ContentPart::Document(
        data="base64pdf",
        media_type="application/pdf",
        title=Some("report.pdf"),
      ),
    ]),
  )
  match message_to_content(msg) {
    Some(content) => {
      inspect(content.parts.length(), content="2")
      match content.parts[1] {
        GeminiPart::InlineData(mime_type~, data~) => {
          inspect(mime_type, content="application/pdf")
          inspect(data, content="base64pdf")
        }
        _ => fail("Expected InlineData for document")
      }
    }
    None => fail("Expected content")
  }
}

///|
test "parse_stream_chunk extracts executableCode and codeExecutionResult" {
  let chunk : Json = {
    "candidates": Json::array([
      {
        "content": {
          "role": "model",
          "parts": Json::array([
            { "text": "Let me calculate." },
            { "executableCode": { "language": "PYTHON", "code": "print(2+2)" } },
            {
              "codeExecutionResult": {
                "outcome": "OUTCOME_OK",
                "output": "4\n",
              },
            },
          ]),
        },
      },
    ]),
  }
  match parse_stream_chunk(chunk) {
    Some((text, _calls)) => {
      assert_true(text.contains("Let me calculate"))
      assert_true(text.contains("```python"))
      assert_true(text.contains("print(2+2)"))
      assert_true(text.contains("OUTCOME_OK"))
      assert_true(text.contains("4"))
    }
    None => fail("Expected parsed chunk")
  }
}

///|
test "parse_response canonicalizes wrapped Gemini structured output" {
  let response : Json = {
    "candidates": [
      {
        "content": {
          "role": "model",
          "parts": [
            {
              "text": "```json\n{\"lookup_verification_url_response\":{\"content\":\"{\\\"url\\\":\\\"https://example.com/interop-check\\\"}\"}}\n```",
            },
          ],
        },
      },
    ],
  }
  match parse_response(response) {
    @types.ModelResponse::Text(text) =>
      assert_eq(text, "{\"url\":\"https://example.com/interop-check\"}")
    _ => fail("Expected normalized Gemini text response")
  }
}

///|
test "GeminiToResponsesTranslator handles SAFETY finishReason" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_safety_test",
    model="gemini-2.0-flash",
  )
  let safety_event : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": Json::array([
        {
          "finishReason": "SAFETY",
          "content": { "role": "model", "parts": Json::array([]) },
        },
      ]),
    },
  }
  let events = translator.translate(safety_event)
  let mut found_completed = false
  for e in events {
    match e {
      ("response.completed", data) =>
        match data {
          {
            "response": {
              "status": String("failed"),
              "error": { "type": String("content_filter"), .. },
              ..
            },
            ..
          } => found_completed = true
          _ => ()
        }
      _ => ()
    }
  }
  assert_true(found_completed)
}
