///|
/// Tests for gateway native functions
test "expand_env expands environment variable" {
  @sys.set_env_var("TEST_VAR_12345", "test_value")
  let result = expand_env("${TEST_VAR_12345}")
  assert_eq(result, "test_value")
  @sys.unset_env_var("TEST_VAR_12345")
}

///|
test "expand_env returns original if not env var format" {
  assert_eq(expand_env("plain_string"), "plain_string")
  assert_eq(expand_env("$NOT_ENV"), "$NOT_ENV")
  assert_eq(expand_env("{NOT_ENV}"), "{NOT_ENV}")
}

///|
test "expand_env returns empty for missing env var" {
  let result = expand_env("${NONEXISTENT_VAR_99999}")
  assert_eq(result, "")
}

///|
test "responses_stream_translation_source_api routes stdio backends through chat translation" {
  assert_eq(
    responses_stream_translation_source_api(
      @gw.ModelApi::CodexAppServer,
    ),
    None,
  )
  assert_eq(
    responses_stream_translation_source_api(
      @gw.ModelApi::ClaudeMcpServe,
    ),
    Some(@gw.ModelApi::ClaudeMcpServe),
  )
  assert_eq(
    responses_stream_translation_source_api(
      @gw.ModelApi::OpenAIResponses,
    ),
    None,
  )
}

///|
test "responses_error_status recognizes canonical Responses errors" {
  assert_eq(
    responses_error_status({ "error": { "code": 429, "message": "slow down" } }),
    Some(429),
  )
  assert_eq(
    responses_error_status({ "error": { "message": "boom" } }),
    Some(500),
  )
  assert_eq(responses_error_status({ "id": "resp_ok" }), None)
}

///|
test "translated_failure_status maps translated error carriers to HTTP status" {
  assert_eq(
    translated_failure_status(
      @gw.GatewaySurface::OpenAI,
      "{\"error\":{\"type\":\"rate_limit_error\",\"code\":429,\"message\":\"slow down\"}}",
    ),
    429,
  )
  assert_eq(
    translated_failure_status(
      @gw.GatewaySurface::Anthropic,
      "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"bad input\"}}",
    ),
    400,
  )
  assert_eq(
    translated_failure_status(
      @gw.GatewaySurface::Gemini,
      "{\"error\":{\"code\":503,\"message\":\"boom\",\"status\":\"UNAVAILABLE\"}}",
    ),
    503,
  )
}
