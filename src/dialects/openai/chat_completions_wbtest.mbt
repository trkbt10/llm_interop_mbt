///|
/// Whitebox coverage for OpenAI Chat Completions helpers and fallback branches

///|
test "message and builder helpers cover names, multimodal fallbacks, and builtin tools" {
  let named_multimodal = message_to_json(
    @types.ModelMessage::User(
      content="ignored",
      name=Some("alice"),
      content_parts=Some([
        @types.ContentPart::Text("Describe this"),
        @types.ContentPart::ImageUrl(
          url="https://example.com/cat.png",
          detail=None,
        ),
      ]),
    ),
  )
  match named_multimodal {
    { "role": "user", "name": "alice", "content": Array(parts), .. } => {
      assert_eq(parts.length(), 2)
      match parts[1] {
        { "type": "image_url", "image_url": { "url": String(url), .. }, .. } =>
          assert_eq(url, "https://example.com/cat.png")
        _ => fail("Expected named multimodal user message")
      }
    }
    _ => fail("Expected named multimodal user message")
  }

  let named_plain = message_to_json(
    @types.ModelMessage::User(
      content="Hello",
      name=Some("alice"),
      content_parts=None,
    ),
  )
  match named_plain {
    { "role": "user", "name": "alice", "content": "Hello", .. } => ()
    _ => fail("Expected named plain user message")
  }

  let assistant_plain = message_to_json(
    @types.ModelMessage::Assistant(content="Done", tool_calls=None),
  )
  match assistant_plain {
    { "role": "assistant", "content": "Done", .. } => ()
    _ => fail("Expected plain assistant message")
  }

  let parts = content_parts_to_openai_json([
    @types.ContentPart::ImageUrl(
      url="https://example.com/plain.png",
      detail=None,
    ),
    @types.ContentPart::Document(
      data="BASE64PDF",
      media_type="application/pdf",
      title=None,
    ),
    @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
    @types.ContentPart::Video(data="VIDEO", media_type="video/mp4"),
  ])
  assert_eq(parts.length(), 4)
  match parts[0] {
    { "type": "image_url", "image_url": { "url": String(url), .. }, .. } =>
      assert_eq(url, "https://example.com/plain.png")
    _ => fail("Expected image part")
  }
  match parts[1] {
    { "type": "file", "file": { "file_data": String(data), .. }, .. } =>
      assert_eq(data, "data:application/pdf;base64,BASE64PDF")
    _ => fail("Expected document file part")
  }
  match parts[2] {
    { "type": "text", "text": String(text), .. } => {
      assert_true(text.contains("Remote file URL input"))
      assert_true(text.contains("https://example.com/report.pdf"))
    }
    _ => fail("Expected file-url fallback text part")
  }
  match parts[3] {
    { "type": "text", "text": String(text), .. } =>
      assert_true(text.contains("Video content"))
    _ => fail("Expected video fallback text part")
  }

  let generic_builtin = @types.ToolDefinition::builtin(
    type_="code_execution",
    name="code_execution",
    description="Run code",
  )
  match tool_to_json(generic_builtin) {
    { "type": "function", "function": { "name": "code_execution", .. }, .. } =>
      ()
    _ => fail("Expected generic builtin fallback tool")
  }
  match
    tool_to_json(@types.ToolDefinition::builtin(type_="web_search_preview")) {
    { "type": "function", "function": { "name": String(name), .. }, .. } =>
      assert_eq(name, @types.web_search_tool_name())
    _ => fail("Expected generic builtin web search tool")
  }
  match tool_to_json(@types.ToolDefinition::web_search_preview_2025_03_11()) {
    { "type": "function", "function": { "name": String(name), .. }, .. } =>
      assert_eq(name, @types.web_search_tool_name())
    _ => fail("Expected explicit web search tool")
  }
  let tools_json = tools_to_json([
    generic_builtin,
    @types.ToolDefinition::web_search_preview(),
  ])
  assert_eq(tools_json.length(), 2)

  let body = build_chat_body(
    "gpt-4o",
    [
      @types.ModelMessage::System("Be concise"),
      @types.ModelMessage::User(content="Hi", name=None, content_parts=None),
    ],
    [generic_builtin],
    temperature=Some(0.2),
  )
  match body {
    {
      "model": "gpt-4o",
      "messages": Array(messages),
      "temperature": Number(temp, ..),
      "tools": Array(tools),
      "tool_choice": "auto",
      ..
    } => {
      assert_eq(messages.length(), 2)
      assert_eq(temp, 0.2)
      assert_eq(tools.length(), 1)
    }
    _ => fail("Expected built chat body")
  }
}

///|
test "parse chat helpers cover audio, malformed tool calls, and error fallbacks" {
  match parse_chat_response({ "choices": Json::array([]) }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "No choices in response")
    _ => fail("Expected no-choices error")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": { "role": "assistant", "content": "Preface" },
          "finish_reason": "tool_calls",
        },
      ]),
    }) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Preface")
    _ => fail("Expected text fallback when tool_calls field is missing")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": "Narration",
            "audio": { "data": "BASE64AUDIO", "transcript": "Audio transcript" },
          },
          "finish_reason": "stop",
        },
      ]),
    }) {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 2)
          match parts[0] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "Narration")
            _ => fail("Expected output text before audio")
          }
          match parts[1] {
            @types.ResponseContentPart::AudioOutput(data~, transcript~) => {
              assert_eq(data, "BASE64AUDIO")
              assert_eq(transcript, "Audio transcript")
            }
            _ => fail("Expected audio output part")
          }
        }
        None => fail("Expected audio content parts")
      }
    _ => fail("Expected RichText audio response")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "audio": { "data": "BASE64AUDIO", "transcript": "Audio transcript" },
          },
          "finish_reason": "stop",
        },
      ]),
    }) {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 2)
          match parts[0] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "Audio transcript")
            _ => fail("Expected transcript fallback text")
          }
          match parts[1] {
            @types.ResponseContentPart::AudioOutput(data~, transcript~) => {
              assert_eq(data, "BASE64AUDIO")
              assert_eq(transcript, "Audio transcript")
            }
            _ => fail("Expected transcript fallback audio output")
          }
        }
        None => fail("Expected transcript fallback content parts")
      }
    _ => fail("Expected transcript fallback RichText response")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": Json::null(),
            "tool_calls": Json::array([{ "bad": true }]),
          },
          "finish_reason": "tool_calls",
        },
      ]),
    }) {
    @types.ModelResponse::Text(text) => assert_eq(text, "")
    _ => fail("Expected empty text fallback for malformed tool calls")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": Json::null(),
            "tool_calls": Json::array([
              {
                "id": "call_1",
                "function": {
                  "name": "lookup",
                  "arguments": "{\"q\":\"moonbit\"}",
                },
              },
            ]),
          },
          "finish_reason": "tool_calls",
        },
      ]),
    }) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "lookup")
    }
    _ => fail("Expected ToolCalls response")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": Json::null(),
            "tool_calls": Json::array([
              {
                "id": "call_2",
                "function": {
                  "name": "lookup",
                  "arguments": "{\"q\":\"moonbit\"}",
                },
              },
            ]),
          },
          "finish_reason": "stop",
        },
      ]),
    }) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "call_2")
    }
    _ => fail("Expected ToolCalls from null content tool_calls")
  }

  match
    parse_chat_response({
      "choices": Json::array([{ "message": 7, "finish_reason": "stop" }]),
    }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "Invalid message format")
    _ => fail("Expected invalid message error")
  }

  match parse_chat_response({ "choices": Json::array([{ "index": 0 }]) }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "Invalid choice format")
    _ => fail("Expected invalid choice error")
  }

  match parse_chat_response({ "error": { "message": "boom" } }) {
    @types.ModelResponse::ModelError(message) => assert_eq(message, "boom")
    _ => fail("Expected top-level error")
  }
  match parse_chat_response({ "unexpected": true }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "Unknown response format")
    _ => fail("Expected unknown-format error")
  }

  assert_eq(parse_tool_calls(Json::array([{ "bad": true }])).length(), 0)
  assert_eq(parse_tool_calls(Json::null()).length(), 0)
}
