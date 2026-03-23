///|
/// Whitebox coverage for Gemini chat transform helpers and fallbacks

///|
test "request_to_chat covers invalid json and skips non-text parts" {
  assert_eq(
    request_to_chat("not json", "gpt-4.1", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
    "not json",
  )

  let request_body =
    #|{"contents":[{"role":"user","parts":[{"inline_data":{"mime_type":"image/png","data":"AAA"}},{"text":"Hello"},{"functionCall":{"name":"lookup","args":{"q":"moonbit"}}},{"text":"World"}]}]}
  let result = request_to_chat(request_body, "gpt-4.1", {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch {
    _ => fail("Expected OpenAI chat json")
  }
  match json {
    {
      "model": String("gpt-4.1"),
      "messages": [{ "role": String("user"), "content": String(content), .. }],
      ..
    } => assert_eq(content, "Hello\nWorld")
    _ => fail("Expected joined Gemini text parts")
  }
}

///|
test "chat request helpers cover tool lookup, multimodal conversion, and malformed tools" {
  assert_eq(
    find_tool_name_for_id(
      [
        {
          "role": "assistant",
          "tool_calls": Json::array([
            { "id": "call_1", "function": { "name": "lookup" } },
          ]),
        },
      ],
      { "role": "tool", "tool_call_id": "call_1", "content": "done" },
    ),
    "lookup",
  )
  assert_eq(
    find_tool_name_for_id([], { "role": "tool", "tool_call_id": "missing" }),
    "unknown",
  )

  assert_eq(transform_openai_content_to_gemini(Json::string("plain text")), [
    { "text": "plain text" },
  ])
  assert_eq(
    transform_openai_content_to_gemini(
      Json::array([
        { "type": "text", "text": "Alpha" },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/png;base64,QUJD" },
        },
        {
          "type": "image_url",
          "image_url": { "url": "https://example.com/not-supported.png" },
        },
        { "type": "input_audio", "input_audio": { "data": "AAA" } },
      ]),
    ),
    [
      { "text": "Alpha" },
      { "inline_data": { "mime_type": "image/png", "data": "QUJD" } },
    ],
  )
  assert_eq(transform_openai_content_to_gemini(Json::null()), [])

  let gemini_request_body =
    #|{"messages":[{"role":"system","content":"skip"},{"role":"assistant","content":"","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"not-json"}}]},{"role":"tool","content":"done","tool_call_id":"call_1"},{"role":"tool","content":"mystery","tool_call_id":"missing"},{"role":"user","content":[{"type":"text","text":"See image"},{"type":"image_url","image_url":{"url":"data:image/png;base64,QUJD"}},{"type":"image_url","image_url":{"url":"https://example.com/not-supported.png"}}]}],"tools":[{"type":"function","function":{"name":"lookup","description":"Search docs","parameters":{"type":"object"}}},{"type":"web_search_preview"},{"bad":true}],"temperature":0.6}
  let gemini_request = chat_request_to_gemini(gemini_request_body, {
    max_tokens: 2048,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(gemini_request) catch {
    _ => fail("Expected Gemini request json")
  }
  match json {
    {
      "contents": Array(contents),
      "tools": [{ "functionDeclarations": Array(decls), .. }],
      "generationConfig": { "temperature": Number(temp, ..), .. },
      ..
    } => {
      assert_eq(contents.length(), 4)
      match contents[0] {
        {
          "role": String("model"),
          "parts": [
            {
              "functionCall": { "name": String(name), "args": Object(args), .. },
              ..
            },
          ],
          ..
        } => {
          assert_eq(name, "lookup")
          assert_eq(args.length(), 0)
        }
        _ => fail("Expected assistant tool call content")
      }
      match contents[1] {
        {
          "role": String("user"),
          "parts": [{ "functionResponse": { "name": String(name), .. }, .. }],
          ..
        } => assert_eq(name, "lookup")
        _ => fail("Expected resolved tool result")
      }
      match contents[2] {
        {
          "role": String("user"),
          "parts": [{ "functionResponse": { "name": String(name), .. }, .. }],
          ..
        } => assert_eq(name, "unknown")
        _ => fail("Expected unknown tool result fallback")
      }
      match contents[3] {
        { "role": String("user"), "parts": Array(parts), .. } =>
          assert_eq(parts.length(), 2)
        _ => fail("Expected multimodal user content")
      }
      assert_eq(decls.length(), 1)
      assert_eq(temp, 0.6)
    }
    _ => fail("Expected Gemini request structure")
  }
}

///|
test "response helpers cover fallback candidates and invalid args" {
  assert_eq(response_to_chat("not json"), "not json")

  let response_body =
    #|{"candidates":[{"content":{"parts":[{"text":"Alpha"},{"text":"Beta"}],"role":"model"}},{"finishReason":"STOP"}]}
  let response = response_to_chat(response_body)
  let json : Json = @json.parse(response) catch {
    _ => fail("Expected chat response json")
  }
  match json {
    {
      "id": String(id),
      "choices": [
        { "message": { "content": String(first), .. }, .. },
        { "message": { "content": String(second), .. }, .. },
      ],
      ..
    } => {
      assert_eq(id, "gemini-2")
      assert_eq(first, "Alpha\n\nBeta")
      assert_eq(second, "")
    }
    _ => fail("Expected Gemini chat response choices")
  }

  let gemini_response_body =
    #|{"choices":[{"message":{"content":"Checking...","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"not-json"}}]}}]}
  let gemini_response = chat_response_to_gemini(gemini_response_body)
  let gemini_json : Json = @json.parse(gemini_response) catch {
    _ => fail("Expected Gemini response json")
  }
  match gemini_json {
    {
      "candidates": [
        {
          "content": {
            "role": String("model"),
            "parts": [
              { "text": String("Checking..."), .. },
              {
                "functionCall": {
                  "name": String("lookup"),
                  "args": Object(args),
                  ..
                },
                ..
              },
            ],
            ..
          },
          ..
        },
      ],
      ..
    } => assert_eq(args.length(), 0)
    _ => fail("Expected Gemini response with function call")
  }

  let empty_response_body =
    #|{"choices":[]}
  let empty_response = chat_response_to_gemini(empty_response_body)
  let empty_json : Json = @json.parse(empty_response) catch {
    _ => fail("Expected empty Gemini response json")
  }
  match empty_json {
    {
      "candidates": [
        { "content": { "parts": [{ "text": String(""), .. }], .. }, .. },
      ],
      ..
    } => ()
    _ => fail("Expected empty text fallback candidate")
  }
}

///|
test "structured output helpers unwrap Gemini wrappers and fences" {
  assert_eq(
    normalize_structured_output_text(
      "```json\n{\"lookup_response\":{\"url\":\"https://example.com\"}}\n```",
    ),
    "{\"url\":\"https://example.com\"}",
  )
  assert_eq(
    normalize_structured_output_text(
      "{\"lookup_response\":{\"content\":\"{\\\"url\\\":\\\"https://example.com/nested\\\"}\"}}",
    ),
    "{\"url\":\"https://example.com/nested\"}",
  )
  assert_eq(
    normalize_structured_output_fragments(
      [
        "{\"lookup_response\":", "{\"content\":\"{\\\"url\\\":\\\"https://example.com/fragments\\\"}\"}}",
      ],
      "\n",
    ),
    "{\"url\":\"https://example.com/fragments\"}",
  )
  assert_eq(normalize_structured_output_text("plain text"), "plain text")
}

///|
test "error conversion covers passthrough and unknown fallback" {
  assert_eq(openai_error_to_gemini("not json"), "not json")

  let empty_error_body =
    #|{}
  let fallback_json : Json = @json.parse(
    openai_error_to_gemini(empty_error_body),
  ) catch {
    _ => fail("Expected Gemini error json")
  }
  match fallback_json {
    {
      "error": {
        "code": Number(code, ..),
        "message": String("Unknown error"),
        "status": String("INVALID_ARGUMENT"),
        ..
      },
      ..
    } => assert_eq(code.to_int(), 400)
    _ => fail("Expected unknown Gemini error fallback")
  }
}
