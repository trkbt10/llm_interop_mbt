///|
/// Whitebox coverage for Gemini chat transform helpers and validation

///|
test "request_to_chat skips non-text parts in valid Gemini content" {
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
test "panic request/response helpers reject invalid json" {
  ignore(
    request_to_chat("not json", "gpt-4.1", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
  )
  ignore(response_to_chat("not json"))
  ignore(chat_response_to_gemini("not json"))
}

///|
test "chat request helpers cover tool lookup and supported multimodal conversion" {
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
    #|{"messages":[{"role":"system","content":"skip"},{"role":"assistant","content":"","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\"q\":\"moonbit\"}"}}]},{"role":"tool","content":"done","tool_call_id":"call_1"},{"role":"user","content":[{"type":"text","text":"See image"},{"type":"image_url","image_url":{"url":"data:image/png;base64,QUJD"}}]}],"tools":[{"type":"function","function":{"name":"lookup","description":"Search docs","parameters":{"type":"object"}}},{"type":"web_search_preview"},{"bad":true}],"temperature":0.6}
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
      assert_eq(contents.length(), 3)
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
          assert_eq(args, { "q": "moonbit" })
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
test "panic chat request helpers reject remote image URLs" {
  ignore(
    transform_openai_content_to_gemini(
      Json::array([
        {
          "type": "image_url",
          "image_url": { "url": "https://example.com/not-supported.png" },
        },
      ]),
    ),
  )
}

///|
test "response helpers cover empty candidates and valid args" {
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
    #|{"choices":[{"message":{"content":"Checking...","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\"q\":\"moonbit\"}"}}]}}]}
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
    } => assert_eq(args, { "q": "moonbit" })
    _ => fail("Expected Gemini response with function call")
  }

  let empty_response_body =
    #|{"choices":[{"message":{"content":""}}]}
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
test "panic response_to_chat rejects unsupported Gemini response parts" {
  ignore(
    response_to_chat(
      "{\"candidates\":[{\"content\":{\"parts\":[{\"executableCode\":{\"language\":\"python\",\"code\":\"print(1)\"}}],\"role\":\"model\"}}]}",
    ),
  )
}

///|
test "panic chat request helpers reject unresolved tool results" {
  let body =
    #|{"messages":[{"role":"tool","content":"mystery","tool_call_id":"missing"}]}
  ignore(
    chat_request_to_gemini(body, {
      max_tokens: 2048,
      max_tokens_field: "max_tokens",
    }),
  )
}

///|
test "panic chat request helpers reject malformed tool arguments" {
  let body =
    #|{"messages":[{"role":"assistant","tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"not-json"}}]}]}
  ignore(
    chat_request_to_gemini(body, {
      max_tokens: 2048,
      max_tokens_field: "max_tokens",
    }),
  )
}

///|
test "panic chat response helpers reject malformed tool arguments" {
  let body =
    #|{"choices":[{"message":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"lookup","arguments":"not-json"}}]}}]}
  ignore(chat_response_to_gemini(body))
}

///|
test "panic chat response helpers reject empty choices" {
  ignore(chat_response_to_gemini("{\"choices\":[]}"))
}

///|
test "panic response_to_chat rejects grounding without chat attribution url" {
  ignore(
    response_to_chat(
      "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"MoonBit docs\"}],\"role\":\"model\"},\"groundingMetadata\":{\"groundingChunks\":[{\"retrievedContext\":{\"title\":\"Docs\",\"text\":\"MoonBit docs\"}}],\"groundingSupports\":[{\"groundingChunkIndices\":[0],\"segment\":{\"text\":\"MoonBit\",\"startIndex\":0,\"endIndex\":7}}]},\"finishReason\":\"STOP\"}]}",
    ),
  )
}

///|
test "chat response helpers convert OpenAI chat annotations to Gemini grounding metadata" {
  let response = chat_response_to_gemini(
    "{\"choices\":[{\"message\":{\"content\":\"hi\",\"annotations\":[{\"type\":\"url_citation\",\"url_citation\":{\"title\":\"Docs\",\"url\":\"https://example.com\",\"start_index\":0,\"end_index\":2}}]}}]}",
  )
  let json : Json = @json.parse(response) catch { _ => fail("parse error") }
  match json {
    {
      "candidates": [
        {
          "groundingMetadata": {
            "groundingChunks": [
              { "web": { "uri": String(url), "title": String(title), .. }, .. },
            ],
            "groundingSupports": [
              {
                "segment": {
                  "text": String(text),
                  "startIndex": Number(start, ..),
                  "endIndex": Number(end_, ..),
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
    } => {
      assert_eq(url, "https://example.com")
      assert_eq(title, "Docs")
      assert_eq(text, "hi")
      assert_eq(start.to_int(), 0)
      assert_eq(end_.to_int(), 2)
    }
    _ => fail("Expected grounding metadata")
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
test "error conversion preserves payloads and maps failure kinds" {
  let malformed_json : Json = @json.parse(openai_error_to_gemini("not json")) catch {
    _ => fail("Expected Gemini error json")
  }
  match malformed_json {
    {
      "error": {
        "code": Number(code, ..),
        "message": String("not json"),
        "status": String("INTERNAL"),
        ..
      },
      ..
    } => assert_eq(code.to_int(), 500)
    _ => fail("Expected malformed source body to become a Gemini error")
  }

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
        "message": String("{}"),
        "status": String("INTERNAL"),
        ..
      },
      ..
    } => assert_eq(code.to_int(), 500)
    _ => fail("Expected payload-preserving Gemini error")
  }

  let rate_limited_json : Json = @json.parse(
    openai_error_to_gemini(
      "{\"error\":{\"message\":\"slow down\",\"type\":\"rate_limit_error\"}}",
    ),
  ) catch {
    _ => fail("Expected Gemini error json")
  }
  match rate_limited_json {
    {
      "error": {
        "code": Number(code, ..),
        "message": String("slow down"),
        "status": String("RESOURCE_EXHAUSTED"),
        ..
      },
      ..
    } => assert_eq(code.to_int(), 429)
    _ => fail("Expected mapped rate limit error")
  }

  assert_true(
    is_error({
      "error": { "code": 400, "message": "bad", "status": "INVALID_ARGUMENT" },
    }),
  )
  assert_false(is_error({ "error": { "message": "bad" } }))

  let openai_json : Json = @json.parse(
    error_to_openai({
      "code": 429,
      "message": "slow down",
      "status": "RESOURCE_EXHAUSTED",
    }),
  ) catch {
    _ => fail("Expected OpenAI error json")
  }
  match openai_json {
    {
      "error": {
        "message": String("slow down"),
        "type": String("rate_limit_error"),
        ..
      },
      ..
    } => ()
    _ => fail("Expected OpenAI rate limit error")
  }

  let anthropic_json : Json = @json.parse(
    error_to_anthropic({
      "code": 403,
      "message": "nope",
      "status": "PERMISSION_DENIED",
    }),
  ) catch {
    _ => fail("Expected Anthropic error json")
  }
  match anthropic_json {
    {
      "type": String("error"),
      "error": {
        "message": String("nope"),
        "type": String("permission_error"),
        ..
      },
      ..
    } => ()
    _ => fail("Expected Anthropic permission error")
  }
}
