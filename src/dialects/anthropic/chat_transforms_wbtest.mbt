///|
/// Whitebox tests for Anthropic chat transform validation branches

///|
fn parse_test_json(json : String) -> Json raise Failure {
  @json.parse(json) catch {
    _ => fail("parse error")
  }
}

///|
test "request and content transforms ignore malformed entries and preserve scalar fallbacks" {
  let request = request_to_chat(
    "{\"messages\":[{\"role\":\"user\",\"content\":\"ok\"},{\"content\":\"missing-role\"}]}",
    { max_tokens: 0, max_tokens_field: "max_completion_tokens" },
  )
  let request_json : Json = @json.parse(request) catch {
    _ => fail("parse error")
  }
  match request_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 1)
    _ => fail("Expected filtered messages")
  }

  match
    transform_openai_content_to_anthropic(
      Json::array([
        Json::object({ "type": Json::string("unknown") }),
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("kept"),
        }),
      ]),
    ) {
    Array(parts) => {
      assert_eq(parts.length(), 1)
      match parts[0] {
        { "type": String("text"), "text": String(text), .. } =>
          assert_eq(text, "kept")
        _ => fail("Expected retained text block")
      }
    }
    _ => fail("Expected anthropic content array")
  }

  match transform_openai_content_to_anthropic(Json::number(1.0)) {
    Number(value, ..) => assert_eq(value, 1.0)
    _ => fail("Expected scalar fallback")
  }
}

///|
test "response_to_chat keeps valid text and ignores unknown non-tool blocks" {
  let response = response_to_chat(
    "{\"id\":\"msg_x\",\"model\":\"claude\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"},{\"type\":\"unknown\"}]}",
  )
  let response_json : Json = @json.parse(response) catch {
    _ => fail("parse error")
  }
  match response_json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "hi")
    _ => fail("Expected OpenAI response")
  }
}

///|
test "Anthropic error helpers preserve payloads and extract error payloads" {
  let openai_error = parse_test_json(error_to_openai({}))
  match openai_error {
    { "error": { "message": String(message), "type": String(kind), .. }, .. } => {
      assert_eq(message, "{}")
      assert_eq(kind, "api_error")
    }
    _ => fail("Expected OpenAI error shape")
  }

  let gemini_error = parse_test_json(error_to_gemini({}))
  match gemini_error {
    {
      "error": { "message": String(message), "status": String(status), .. },
      ..
    } => {
      assert_eq(message, "{}")
      assert_eq(status, "INVALID_ARGUMENT")
    }
    _ => fail("Expected Gemini error shape")
  }

  let anthropic_error = parse_test_json(openai_error_to_anthropic("{}"))
  match anthropic_error {
    { "error": { "message": String(message), "type": String(kind), .. }, .. } => {
      assert_eq(message, "{}")
      assert_eq(kind, "api_error")
    }
    _ => fail("Expected Anthropic error shape")
  }

  assert_true(is_error({ "type": "error", "error": {} }))
  assert_false(is_error({}))

  match extract_error({ "type": "error", "error": { "message": "bad" } }) {
    Some({ "message": String(message), .. }) => assert_eq(message, "bad")
    _ => fail("Expected extracted error payload")
  }
  assert_eq(extract_error({}), None)
}

///|
test "panic chat_request_to_anthropic rejects malformed tool arguments" {
  ignore(
    chat_request_to_anthropic(
      "{\"messages\":[{\"role\":\"assistant\",\"tool_calls\":[{\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"not-json\"}}]}]}",
      { max_tokens: 0, max_tokens_field: "max_completion_tokens" },
    ),
  )
}

///|
test "panic response_to_chat rejects missing ids" {
  ignore(
    response_to_chat(
      "{\"model\":\"claude\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}",
    ),
  )
}

///|
test "panic response_to_chat rejects malformed tool_use blocks" {
  ignore(
    response_to_chat(
      "{\"id\":\"msg_x\",\"model\":\"claude\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_1\"}]}",
    ),
  )
}

///|
test "panic chat_response_to_anthropic rejects missing ids" {
  ignore(chat_response_to_anthropic("{\"model\":\"gpt-4.1\",\"choices\":[]}"))
}

///|
test "panic chat_response_to_anthropic rejects empty choices" {
  ignore(
    chat_response_to_anthropic(
      "{\"id\":\"chatcmpl-1\",\"model\":\"gpt-4.1\",\"choices\":[]}",
    ),
  )
}

///|
test "panic chat_response_to_anthropic rejects malformed tool arguments" {
  ignore(
    chat_response_to_anthropic(
      "{\"id\":\"chatcmpl-1\",\"model\":\"gpt-4.1\",\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"not-json\"}}]}}]}",
    ),
  )
}

///|
test "panic chat_response_to_anthropic rejects incomplete tool calls" {
  ignore(
    chat_response_to_anthropic(
      "{\"id\":\"chatcmpl-1\",\"model\":\"gpt-4.1\",\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_bad\"}]}}]}",
    ),
  )
}
