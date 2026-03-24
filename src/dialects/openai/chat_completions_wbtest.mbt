///|
/// Whitebox coverage for OpenAI Chat Completions helpers and validation branches

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

  let annotations = chat_annotations_from_response_annotations([
    @types.ResponseAnnotation::url_citation(
      url="https://example.com/docs",
      title=Some("Docs"),
      start_index=0,
      end_index=4,
    ),
    @types.ResponseAnnotation::web_search_result_citation(
      cited_text="MoonBit",
      encrypted_index="enc_1",
      title="MoonBit Search",
      url="https://example.com/search",
      start_index=5,
      end_index=12,
    ),
    @types.ResponseAnnotation::document_page_citation(
      cited_text="MoonBit",
      document_index=0,
      document_title="Spec",
      file_id="file_spec",
      start_page_number=1,
      end_page_number=1,
      start_index=0,
      end_index=7,
    ),
  ])
  assert_eq(annotations.length(), 2)
  match annotations[0] {
    {
      "type": "url_citation",
      "url_citation": {
        "title": String(title),
        "url": String(url),
        "start_index": Number(start_index, ..),
        "end_index": Number(end_index, ..),
        ..
      },
      ..
    } => {
      assert_eq(title, "Docs")
      assert_eq(url, "https://example.com/docs")
      assert_eq(start_index.to_int(), 0)
      assert_eq(end_index.to_int(), 4)
    }
    _ => fail("Expected UrlCitation chat annotation")
  }
  match annotations[1] {
    {
      "type": "url_citation",
      "url_citation": {
        "title": String(title),
        "url": String(url),
        "start_index": Number(start_index, ..),
        "end_index": Number(end_index, ..),
        ..
      },
      ..
    } => {
      assert_eq(title, "MoonBit Search")
      assert_eq(url, "https://example.com/search")
      assert_eq(start_index.to_int(), 5)
      assert_eq(end_index.to_int(), 12)
    }
    _ => fail("Expected down-converted web search annotation")
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
    @types.ModelResponse::ModelError(message) =>
      assert_eq(
        message, "OpenAI chat response signaled tool_calls without a tool_calls payload",
      )
    _ => fail("Expected tool_calls payload error")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": "Weather details",
            "annotations": Json::array([
              {
                "type": "url_citation",
                "url_citation": {
                  "title": "Weather Source",
                  "url": "https://example.com/weather",
                  "start_index": 0,
                  "end_index": 7,
                },
              },
            ]),
          },
          "finish_reason": "stop",
        },
      ]),
    }) {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::UrlCitation(
          title~,
          url~,
          start_index~,
          end_index~
        ) => {
          assert_eq(title, Some("Weather Source"))
          assert_eq(url, "https://example.com/weather")
          assert_eq(start_index, 0)
          assert_eq(end_index, 7)
        }
        _ => fail("Expected parsed url citation")
      }
    }
    _ => fail("Expected RichText with annotations")
  }

  match
    parse_chat_response({
      "choices": Json::array([
        {
          "message": {
            "role": "assistant",
            "content": "Checking...",
            "annotations": Json::array([
              {
                "type": "url_citation",
                "url_citation": {
                  "title": "Weather Source",
                  "url": "https://example.com/weather",
                  "start_index": 0,
                  "end_index": 7,
                },
              },
            ]),
            "tool_calls": Json::array([
              {
                "id": "call_lookup",
                "function": {
                  "name": "lookup",
                  "arguments": "{\"q\":\"weather\"}",
                },
              },
            ]),
          },
          "finish_reason": "tool_calls",
        },
      ]),
    }) {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "lookup")
      assert_eq(rich.content, "Checking...")
      assert_eq(rich.annotations.length(), 1)
    }
    _ => fail("Expected ToolCallsWithContent annotations")
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
}

///|
test "panic parse_chat_response rejects malformed tool call arguments" {
  parse_chat_response({
    "choices": Json::array([
      {
        "message": {
          "role": "assistant",
          "tool_calls": Json::array([
            {
              "id": "call_bad",
              "function": { "name": "lookup", "arguments": "not-json" },
            },
          ]),
        },
        "finish_reason": "tool_calls",
      },
    ]),
  })
  |> ignore
}

///|
test "panic parse_chat_response rejects malformed tool call payload" {
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
  })
  |> ignore
}

///|
test "panic parse_tool_calls rejects non-array payloads" {
  parse_tool_calls(Json::null()) |> ignore
}
