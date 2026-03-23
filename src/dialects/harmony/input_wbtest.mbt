///|
/// Whitebox coverage for Responses input parsing helpers

///|
test "responses_input_to_messages covers pending flushes, builtin fallbacks, and unknown items" {
  let messages = responses_input_to_messages([
    { "type": "function_call", "name": "missing_id", "arguments": "{}" },
    {
      "type": "function_call",
      "id": "fc_by_id",
      "name": "lookup",
      "arguments": "{}",
    },
    {
      "role": "user",
      "content": Json::array([
        { "type": "output_text", "text": "hello" },
        Json::string(" world"),
      ]),
    },
    {
      "type": "function_call",
      "call_id": "fc_bad_args",
      "name": "calc",
      "arguments": "{",
    },
    { "role": "assistant", "content": Json::array([Json::string("preface")]) },
    { "type": "web_search_call", "id": "ws_no_action" },
    {
      "type": "computer_call_output",
      "id": "computer_output_1",
      "output": { "ok": true },
    },
    { "type": "computer_call", "id": "computer_call_1", "status": "completed" },
    { "value": 1 },
  ])

  assert_eq(messages.length(), 7)

  match messages[0] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].id, "")
      assert_eq(calls[0].name, "missing_id")
      assert_eq(calls[1].id, "fc_by_id")
      assert_eq(calls[1].name, "lookup")
    }
    _ => fail("Expected flushed function call assistant")
  }
  match messages[1] {
    @types.ModelMessage::User(content~, content_parts~, ..) => {
      assert_eq(content, "hello world")
      assert_eq(content_parts, None)
    }
    _ => fail("Expected user message")
  }
  match messages[2] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "fc_bad_args")
      assert_eq(calls[0].arguments, {})
    }
    _ => fail("Expected second flushed tool call assistant")
  }
  match messages[3] {
    @types.ModelMessage::Assistant(content~, tool_calls=None) =>
      assert_eq(content, "preface")
    _ => fail("Expected assistant text")
  }
  match messages[4] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "ws_no_action")
      assert_eq(calls[0].kind, @types.ToolCallKind::WebSearch)
      assert_eq(calls[0].name, @types.web_search_tool_name())
    }
    _ => fail("Expected flushed web search call")
  }
  match messages[5] {
    @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
      assert_eq(tool_call_id, "computer_output_1")
      assert_true(content.contains("computer_call_output"))
    }
    _ => fail("Expected builtin output wrapper")
  }
  match messages[6] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "computer_call_1")
      assert_eq(
        calls[0].kind,
        @types.ToolCallKind::Builtin(builtin_type="computer_call"),
      )
      assert_eq(calls[0].name, "computer_call")
    }
    _ => fail("Expected trailing builtin call flush")
  }
}

///|
test "input helper functions cover builtin ids, text extraction, multimodal branches, and data-url fallbacks" {
  assert_eq(extract_responses_tool_item_id({ "call_id": "call_1" }), "call_1")
  assert_eq(
    extract_responses_tool_item_id({ "approval_request_id": "approval_1" }),
    "approval_1",
  )
  assert_eq(extract_responses_tool_item_id({ "id": "id_1" }), "id_1")
  assert_eq(extract_responses_tool_item_id({}), "")

  assert_eq(
    extract_text_content(
      Json::array([{ "type": "output_text", "text": "A" }, Json::string("B")]),
    ),
    "AB",
  )
  assert_eq(extract_text_content(Json::boolean(true)), "")

  match
    extract_content_parts(
      Json::array([
        { "type": "input_image", "image_url": "data:image/png;base64,AAA" },
      ]),
    ) {
    Some(parts) =>
      match parts[0] {
        @types.ContentPart::ImageBase64(data~, media_type~) => {
          assert_eq(data, "AAA")
          assert_eq(media_type, "image/png")
        }
        _ => fail("Expected base64 input image")
      }
    None => fail("Expected image content parts")
  }
  assert_eq(
    extract_content_parts(
      Json::array([{ "type": "input_image", "image_url": "data:broken" }]),
    ),
    None,
  )

  match
    extract_content_parts(
      Json::array([
        {
          "type": "image_url",
          "image_url": {
            "url": "https://example.com/cat.png",
            "detail": "high",
          },
        },
      ]),
    ) {
    Some(parts) =>
      match parts[0] {
        @types.ContentPart::ImageUrl(url~, detail~) => {
          assert_eq(url, "https://example.com/cat.png")
          assert_eq(detail, Some("high"))
        }
        _ => fail("Expected remote image url")
      }
    None => fail("Expected image_url content part")
  }
  match
    extract_content_parts(
      Json::array([
        {
          "type": "image_url",
          "image_url": { "url": "data:image/jpeg;base64,BBB", "detail": "low" },
        },
      ]),
    ) {
    Some(parts) =>
      match parts[0] {
        @types.ContentPart::ImageBase64(data~, media_type~) => {
          assert_eq(data, "BBB")
          assert_eq(media_type, "image/jpeg")
        }
        _ => fail("Expected data image_url conversion")
      }
    None => fail("Expected image_url data conversion")
  }
  assert_eq(
    extract_content_parts(
      Json::array([
        { "type": "image_url", "image_url": { "url": "data:broken" } },
      ]),
    ),
    None,
  )

  match
    extract_content_parts(
      Json::array([
        { "type": "input_audio", "data": "AUDIO1", "format": "wav" },
        {
          "type": "input_audio",
          "input_audio": { "data": "AUDIO2", "format": "mp3" },
        },
        { "type": "file", "file_id": "file_flat" },
        {
          "type": "document",
          "source": {
            "type": "base64",
            "media_type": "application/pdf",
            "data": "PDFDATA",
          },
          "title": "Report",
        },
        { "type": "input_file", "file_id": "file_input" },
        { "type": "input_file", "file_url": "https://example.com/report.pdf" },
        { "type": "input_file", "file_data": "data:text/plain;base64,VEVYVA==" },
        { "type": "unsupported" },
        {
          "type": "document",
          "source": { "type": "file", "file_id": "file_doc" },
        },
        Json::string("trailing text"),
      ]),
    ) {
    Some(parts) => {
      assert_eq(parts.length(), 9)
      match parts[0] {
        @types.ContentPart::Audio(data~, format~) => {
          assert_eq(data, "AUDIO1")
          assert_eq(format, "wav")
        }
        _ => fail("Expected flat input_audio")
      }
      match parts[1] {
        @types.ContentPart::Audio(data~, format~) => {
          assert_eq(data, "AUDIO2")
          assert_eq(format, "mp3")
        }
        _ => fail("Expected nested input_audio")
      }
      match parts[2] {
        @types.ContentPart::FileRef(file_id~, ..) =>
          assert_eq(file_id, "file_flat")
        _ => fail("Expected flattened file ref")
      }
      match parts[3] {
        @types.ContentPart::Document(data~, media_type~, title~) => {
          assert_eq(data, "PDFDATA")
          assert_eq(media_type, "application/pdf")
          assert_eq(title, Some("Report"))
        }
        _ => fail("Expected base64 document")
      }
      match parts[4] {
        @types.ContentPart::FileRef(file_id~, ..) =>
          assert_eq(file_id, "file_input")
        _ => fail("Expected input_file ref")
      }
      match parts[5] {
        @types.ContentPart::FileUrl(url~) =>
          assert_eq(url, "https://example.com/report.pdf")
        _ => fail("Expected input_file url")
      }
      match parts[6] {
        @types.ContentPart::Document(data~, media_type~, title~) => {
          assert_eq(data, "VEVYVA==")
          assert_eq(media_type, "text/plain")
          assert_eq(title, None)
        }
        _ => fail("Expected inline document file")
      }
      match parts[7] {
        @types.ContentPart::FileRef(file_id~, ..) =>
          assert_eq(file_id, "file_doc")
        _ => fail("Expected document file ref")
      }
      match parts[8] {
        @types.ContentPart::Text(text) => assert_eq(text, "trailing text")
        _ => fail("Expected trailing text")
      }
    }
    None => fail("Expected mixed content parts")
  }

  assert_eq(
    extract_content_parts(
      Json::array([{ "type": "input_file", "file_data": "data:broken" }]),
    ),
    None,
  )
  assert_eq(extract_content_parts(Json::boolean(false)), None)

  assert_eq(parse_data_url_simple("plain"), None)
  assert_eq(parse_data_url_simple("data:image/png"), None)
  assert_eq(
    parse_data_url_simple("data:image/png;base64,AAAA"),
    Some(("image/png", "AAAA")),
  )
}

///|
test "json_array_to_strings ignores non-string values" {
  assert_eq(
    json_array_to_strings([
      Json::string("a"),
      Json::number(1.0),
      Json::string("b"),
    ]),
    ["a", "b"],
  )
}
