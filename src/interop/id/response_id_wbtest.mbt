///|
/// Response ID helper tests

///|
test "ResponseIdProvider::format returns expected prefixes and native flags" {
  let chat = ResponseIdProvider::OpenAIChatCompletions.format()
  assert_eq(chat.prefix, "chatcmpl-")
  assert_true(chat.has_native_id)

  let responses = ResponseIdProvider::OpenAIResponsesApi.format()
  assert_eq(responses.prefix, "resp_")
  assert_true(responses.has_native_id)

  let anthropic = ResponseIdProvider::AnthropicClaude.format()
  assert_eq(anthropic.prefix, "msg_")
  assert_true(anthropic.has_native_id)

  let gemini = ResponseIdProvider::GoogleGemini.format()
  assert_eq(gemini.prefix, "gemini-resp-")
  assert_false(gemini.has_native_id)

  let unknown = ResponseIdProvider::Unknown.format()
  assert_eq(unknown.prefix, "resp_")
  assert_false(unknown.has_native_id)
}

///|
test "detect_response_id_provider recognizes known prefixes and unknown" {
  assert_eq(
    detect_response_id_provider("chatcmpl-abc"),
    ResponseIdProvider::OpenAIChatCompletions,
  )
  assert_eq(
    detect_response_id_provider("resp_model"),
    ResponseIdProvider::OpenAIResponsesApi,
  )
  assert_eq(
    detect_response_id_provider("msg_123"),
    ResponseIdProvider::AnthropicClaude,
  )
  assert_eq(
    detect_response_id_provider("gemini-resp-flash"),
    ResponseIdProvider::GoogleGemini,
  )
  assert_eq(
    detect_response_id_provider("opaque-id"),
    ResponseIdProvider::Unknown,
  )
}

///|
test "response ID generation and extraction helpers are deterministic" {
  reset_response_id_counter()
  assert_eq(
    generate_response_id(ResponseIdProvider::OpenAIResponsesApi),
    "resp_1",
  )
  assert_eq(generate_response_id(ResponseIdProvider::AnthropicClaude), "msg_2")
  assert_eq(
    generate_response_id_for_model(
      ResponseIdProvider::GoogleGemini,
      "gemini-2.5-pro",
    ),
    "gemini-resp-gemini-2.5-pro",
  )
  assert_eq(
    extract_response_id_from_json("{\"id\":\"resp_existing\"}"),
    Some("resp_existing"),
  )
  assert_eq(extract_response_id_from_json("{\"status\":\"ok\"}"), None)
  assert_eq(extract_response_id_from_json("not json"), None)
  assert_eq(
    extract_or_generate_response_id(
      "{\"id\":\"msg_native\"}",
      ResponseIdProvider::AnthropicClaude,
      "claude-sonnet",
    ),
    "msg_native",
  )
  assert_eq(
    extract_or_generate_response_id(
      "{\"status\":\"missing-id\"}",
      ResponseIdProvider::OpenAIResponsesApi,
      "gpt-4.1",
    ),
    "resp_gpt-4.1",
  )
  reset_response_id_counter()
}
