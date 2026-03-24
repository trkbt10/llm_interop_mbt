///|
/// Whitebox coverage for Gemini protocol helpers and validation paths

///|
test "message and content helpers cover system, multimodal inputs, empty assistant, and tool results" {
  match message_to_content(@types.ModelMessage::System("Follow the policy")) {
    Some({ role: "user", parts: [GeminiPart::Text(text)] }) =>
      assert_eq(text, "Follow the policy")
    _ => fail("Expected system fallback content")
  }

  match
    message_to_content(
      @types.ModelMessage::User(
        content="ignored",
        name=None,
        content_parts=Some([
          @types.ContentPart::ImageBase64(data="BASE64", media_type="image/png"),
          @types.ContentPart::FileRef(
            file_id="files/abc",
            media_type=Some("application/pdf"),
          ),
          @types.ContentPart::Video(data="VIDEO", media_type="video/mp4"),
        ]),
      ),
    ) {
    Some(content) => {
      assert_eq(content.role, "user")
      assert_eq(content.parts.length(), 3)
      match content.parts[0] {
        GeminiPart::InlineData(mime_type~, data~) => {
          assert_eq(mime_type, "image/png")
          assert_eq(data, "BASE64")
        }
        _ => fail("Expected inline image data")
      }
      match content.parts[1] {
        GeminiPart::FileData(file_uri~, mime_type~) => {
          assert_eq(file_uri, "files/abc")
          assert_eq(mime_type, Some("application/pdf"))
        }
        _ => fail("Expected file data")
      }
      match content.parts[2] {
        GeminiPart::InlineData(mime_type~, data~) => {
          assert_eq(mime_type, "video/mp4")
          assert_eq(data, "VIDEO")
        }
        _ => fail("Expected inline video data")
      }
    }
    None => fail("Expected multimodal Gemini content")
  }

  match
    message_to_content(
      @types.ModelMessage::Assistant(
        content="Preface",
        tool_calls=Some([
          @types.ToolCallRequest::new(id="call_1", name="lookup", arguments={
            "q": "moonbit",
          }),
        ]),
      ),
    ) {
    Some(content) => {
      assert_eq(content.role, "model")
      assert_eq(content.parts.length(), 2)
      match content.parts[0] {
        GeminiPart::Text(text) => assert_eq(text, "Preface")
        _ => fail("Expected assistant text preface")
      }
      match content.parts[1] {
        GeminiPart::FunctionCall(name~, args~) => {
          assert_eq(name, "lookup")
          assert_eq(args, { "q": "moonbit" })
        }
        _ => fail("Expected function call part")
      }
    }
    None => fail("Expected assistant content")
  }

  match
    message_to_content(
      @types.ModelMessage::Assistant(content="", tool_calls=None),
    ) {
    None => ()
    Some(_) => fail("Expected empty assistant to be skipped")
  }

  let contents = messages_to_contents([
    @types.ModelMessage::Assistant(content="", tool_calls=None),
    @types.ModelMessage::User(content="Hi", name=None, content_parts=None),
  ])
  assert_eq(contents.length(), 1)
  assert_eq(contents[0].role, "user")

  let resolved_contents = messages_to_contents([
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="call_lookup", name="lookup", arguments={}),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_lookup",
      content="{\"ok\":true}",
    ),
  ])
  assert_eq(resolved_contents.length(), 2)
  match resolved_contents[1] {
    { role: "user", parts: [GeminiPart::FunctionResponse(name~, response~)] } => {
      assert_eq(name, "lookup")
      assert_eq(response, { "ok": true })
    }
    _ => fail("Expected resolved tool result content")
  }

  match
    extract_system_instruction([
      @types.ModelMessage::System("One"),
      @types.ModelMessage::User(content="skip", name=None, content_parts=None),
      @types.ModelMessage::System("Two"),
    ]) {
    Some({ parts: [GeminiPart::Text(text)], .. }) => assert_eq(text, "One\nTwo")
    _ => fail("Expected combined system instruction")
  }

  assert_eq(
    gemini_part_to_json(
      GeminiPart::FunctionResponse(name="lookup", response={ "ok": true }),
    ),
    { "functionResponse": { "name": "lookup", "response": { "ok": true } } },
  )
  assert_eq(
    gemini_part_to_json(
      GeminiPart::InlineData(mime_type="image/png", data="AAA"),
    ),
    { "inlineData": { "mimeType": "image/png", "data": "AAA" } },
  )
  assert_eq(
    gemini_part_to_json(
      GeminiPart::FileData(file_uri="files/abc", mime_type=None),
    ),
    { "fileData": { "fileUri": "files/abc" } },
  )
}

///|
test "panic message_to_content rejects tool results without name context" {
  message_to_content(
    @types.ModelMessage::ToolResult(tool_call_id="call_1", content="not-json"),
  )
  |> ignore
}

///|
test "panic messages_to_contents rejects unresolved tool result ids" {
  messages_to_contents([
    @types.ModelMessage::ToolResult(tool_call_id="missing", content="fallback"),
  ])
  |> ignore
}

///|
test "tool and request helpers cover native builtins, normalized bridged builtins, and generation config" {
  assert_eq(build_builtin_tool_json("googleSearch", Json::null()), {
    "googleSearch": {},
  })
  assert_eq(build_builtin_tool_json("custom_builtin", {}), {
    "name": "custom_builtin",
    "description": "",
    "parameters": {},
  })
  assert_eq(
    tool_name_from_builtin("web_search_preview"),
    @types.web_search_tool_name(),
  )
  assert_eq(
    tool_name_from_builtin("web_search_preview_2025_03_11"),
    @types.web_search_tool_name(),
  )

  assert_eq(
    tool_to_json(@types.ToolDefinition::builtin(type_="codeExecution")),
    { "codeExecution": {} },
  )

  let tools_json = tools_to_json([
    @types.ToolDefinition::builtin(type_="googleSearch", config={}),
    @types.ToolDefinition::builtin(type_="custom_builtin", config={}),
    @types.ToolDefinition::new(name="lookup", description="Search", parameters={
      "type": "object",
    }),
  ])
  match tools_json {
    { "googleSearch": Object(obj), "functionDeclarations": Array(decls), .. } => {
      assert_eq(obj.length(), 0)
      assert_eq(decls.length(), 2)
      match decls[0] {
        {
          "name": "custom_builtin",
          "description": "",
          "parameters": Object(parameters),
          ..
        } => assert_eq(parameters.length(), 0)
        _ => fail("Expected normalized builtin declaration")
      }
    }
    _ => fail("Expected Gemini tools object")
  }

  let body = build_body(
    [
      @types.ModelMessage::System("Guide"),
      @types.ModelMessage::User(content="Hi", name=None, content_parts=None),
    ],
    [@types.ToolDefinition::builtin(type_="googleSearch")],
    max_tokens=Some(10),
    temperature=Some(0.2),
    top_p=Some(0.8),
    top_k=Some(4),
    response_format=Some(@types.ResponseFormat::JsonObject),
  )
  match body {
    {
      "contents": Array(contents),
      "systemInstruction": { "parts": Array(system_parts), .. },
      "generationConfig": {
        "maxOutputTokens": Number(max_tokens, ..),
        "temperature": Number(temperature, ..),
        "topP": Number(top_p, ..),
        "topK": Number(top_k, ..),
        "responseMimeType": "application/json",
        ..
      },
      "tools": Array(tools_arr),
      ..
    } => {
      assert_eq(contents.length(), 1)
      assert_eq(system_parts[0], { "text": "Guide" })
      assert_eq(max_tokens.to_int(), 10)
      assert_eq(temperature, 0.2)
      assert_eq(top_p, 0.8)
      assert_eq(top_k.to_int(), 4)
      assert_eq(tools_arr.length(), 1)
    }
    _ => fail("Expected full Gemini request body")
  }

  let tool_followup_body = build_body(
    [
      @types.ModelMessage::User(
        content="Run tool",
        name=None,
        content_parts=None,
      ),
      @types.ModelMessage::Assistant(
        content="",
        tool_calls=Some([
          @types.ToolCallRequest::new(id="gemini_lookup_0", name="lookup", arguments={
            "q": "docs",
          }),
        ]),
      ),
      @types.ModelMessage::ToolResult(
        tool_call_id="gemini_lookup_0",
        content="{\"value\":1}",
      ),
    ],
    [],
  )
  match tool_followup_body {
    { "contents": Array(contents), .. } => {
      assert_eq(contents.length(), 3)
      match contents[1] {
        {
          "role": "model",
          "parts": [{ "functionCall": { "name": "lookup", .. }, .. }],
          ..
        } => ()
        _ => fail("Expected Gemini assistant functionCall")
      }
      match contents[2] {
        {
          "role": "user",
          "parts": [{ "functionResponse": { "name": "lookup", .. }, .. }],
          ..
        } => ()
        _ => fail("Expected resolved Gemini functionResponse followup")
      }
    }
    _ => fail("Expected Gemini followup request body")
  }
}

///|
test "response and stream parsers cover no candidates, invalid candidates, and empty fallbacks" {
  match parse_response({ "candidates": Json::array([]) }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "No candidates in response")
    _ => fail("Expected no-candidates error")
  }

  match
    parse_response({
      "candidates": Json::array([
        {
          "content": {
            "parts": Json::array([
              { "text": "Thinking aloud" },
              {
                "functionCall": { "name": "lookup", "args": { "q": "moonbit" } },
              },
            ]),
          },
        },
      ]),
    }) {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "lookup")
      assert_eq(rich.content, "Thinking aloud")
    }
    _ => fail("Expected tool calls with content")
  }

  match
    parse_response({ "candidates": Json::array([{ "finishReason": "STOP" }]) }) {
    @types.ModelResponse::ModelError(message) =>
      assert_eq(message, "Invalid candidate format")
    _ => fail("Expected invalid candidate error")
  }

  match parse_response({ "error": { "message": "boom" } }) {
    @types.ModelResponse::ModelError(message) => assert_eq(message, "boom")
    _ => fail("Expected provider error")
  }

  match
    parse_stream_chunk({
      "candidates": Json::array([
        {
          "content": {
            "parts": Json::array([{ "text": "Hi" }, { "unknown": true }]),
          },
        },
      ]),
    }) {
    Some((text, tool_calls)) => {
      assert_eq(text, "Hi")
      assert_eq(tool_calls.length(), 0)
    }
    None => fail("Expected parsed stream chunk")
  }
  match
    parse_stream_chunk({
      "candidates": Json::array([{ "finishReason": "STOP" }]),
    }) {
    None => ()
    Some(_) => fail("Expected finishReason-only chunk to be a no-op")
  }
  match parse_stream_chunk({ "promptFeedback": { "blockReason": "SAFETY" } }) {
    None => ()
    Some(_) => fail("Expected promptFeedback-only chunk to be ignored")
  }
  match parse_stream_chunk({ "usageMetadata": { "totalTokenCount": 3 } }) {
    None => ()
    Some(_) => fail("Expected usage metadata chunk to be ignored")
  }
}

///|
test "panic tool helpers reject lossy builtin configs" {
  build_builtin_tool_json("googleSearch", Json::string("ignored")) |> ignore
}

///|
test "panic tool helpers reject bridged builtin config loss" {
  build_builtin_tool_json("custom_builtin", { "flag": true }) |> ignore
}

///|
test "panic parse_function_calls rejects malformed functionCall parts" {
  parse_function_calls([{ "functionCall": { "name": "lookup" } }]) |> ignore
}

///|
test "panic parse_stream_chunk rejects malformed stream chunks" {
  parse_stream_chunk({ "other": true }) |> ignore
}

///|
test "panic parse_stream_chunk rejects empty candidates without metadata" {
  parse_stream_chunk({ "candidates": Json::array([]) }) |> ignore
}

///|
test "panic parse_stream_chunk rejects candidates without content or finishReason" {
  parse_stream_chunk({
    "candidates": Json::array([{ "safetyRatings": Json::array([]) }]),
  })
  |> ignore
}
