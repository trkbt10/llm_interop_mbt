test "build_openai_surface_stream_request uses Gemini stream endpoint for tool translation" {
  let req = build_openai_surface_stream_request(
    provider(
      "gemini",
      @gateway.GoogleGenerativeAI,
      "gemini-key",
      "https://generativelanguage.googleapis.com/v1beta",
    ),
    raw_openai_surface_tool_body(
      "gemini-2.0-flash",
      tool_turn_one_messages("gateway-gemini-stream"),
      None,
      Some(openai_function_tool_choice("lookup_verification_url")),
    ),
    "gemini-2.0-flash",
  )
  let body = req.body.unwrap_or("")
  assert_true(
    req.url.contains(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=gemini-key",
    ),
  )
  assert_false(body.contains("\"stream\":true"))
  assert_true(body.contains("\"functionDeclarations\""))
  assert_true(body.contains("gateway-gemini-stream"))
}

///|
test "build_openai_surface_stream_request uses Gemini stream endpoint for structured translation" {
  let req = build_openai_surface_stream_request(
    provider(
      "gemini",
      @gateway.GoogleGenerativeAI,
      "gemini-key",
      "https://generativelanguage.googleapis.com/v1beta",
    ),
    raw_openai_surface_translation_body(
      "gemini-2.0-flash",
      structured_response_format(),
    ),
    "gemini-2.0-flash",
  )
  let body = req.body.unwrap_or("")
  assert_true(req.url.contains(":streamGenerateContent?alt=sse&key=gemini-key"))
  assert_false(body.contains("\"stream\":true"))
  assert_true(body.contains("\"systemInstruction\""))
  assert_true(body.contains("\"responseMimeType\":\"application/json\""))
  assert_true(body.contains("\"responseJsonSchema\""))
}

///|
