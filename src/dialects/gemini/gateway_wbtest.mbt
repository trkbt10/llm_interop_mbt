///|
/// Whitebox coverage for Gemini gateway path helpers

///|
test "extract_model_from_path extracts model" {
  assert_eq(
    extract_model_from_path("/v1/models/gemini-1.5-flash:generateContent"),
    "gemini-1.5-flash",
  )
}

///|
test "extract_model_from_stream_path extracts model" {
  assert_eq(
    extract_model_from_stream_path(
      "/v1/models/gemini-pro:streamGenerateContent?alt=sse&key=abc",
    ),
    "gemini-pro",
  )
}
