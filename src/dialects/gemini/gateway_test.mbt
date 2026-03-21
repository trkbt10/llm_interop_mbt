///|
/// Gemini gateway tests

///|
test "completion_path builds correct URL" {
  let path = completion_path("/v1beta", "gemini-pro", "test-key")
  inspect(
    path,
    content="/v1beta/models/gemini-pro:generateContent?key=test-key",
  )
}

///|
test "stream_completion_path builds correct URL" {
  let path = stream_completion_path("/v1beta", "gemini-pro", "test-key")
  inspect(
    path,
    content="/v1beta/models/gemini-pro:streamGenerateContent?alt=sse&key=test-key",
  )
}

///|
test "resolve_completion matches generateContent" {
  let body = "{\"contents\":[]}"
  match resolve_completion("POST", "/v1/models/gemini-pro:generateContent", body) {
    Some((dialect, model, _)) => {
      inspect(dialect, content="gemini")
      inspect(model, content="gemini-pro")
    }
    None => fail("Expected Some")
  }
}

///|
test "resolve_completion matches streamGenerateContent" {
  let body = "{\"contents\":[]}"
  match resolve_completion(
    "POST",
    "/v1/models/gemini-pro:streamGenerateContent?alt=sse&key=abc",
    body,
  ) {
    Some((dialect, model, _)) => {
      inspect(dialect, content="gemini")
      inspect(model, content="gemini-pro")
    }
    None => fail("Expected Some")
  }
}

///|
test "resolve_completion rejects GET" {
  inspect(
    resolve_completion("GET", "/v1/models/gemini-pro:generateContent", "{}") is None,
    content="true",
  )
}

///|
test "resolve_completion rejects non-gemini path" {
  inspect(
    resolve_completion("POST", "/v1/chat/completions", "{}") is None,
    content="true",
  )
}

///|
test "extract_model_from_path extracts model" {
  inspect(
    extract_model_from_path("/v1/models/gemini-1.5-flash:generateContent"),
    content="gemini-1.5-flash",
  )
}

///|
test "extract_model_from_stream_path extracts model" {
  inspect(
    extract_model_from_stream_path(
      "/v1/models/gemini-pro:streamGenerateContent?alt=sse&key=abc",
    ),
    content="gemini-pro",
  )
}

///|
test "auth_headers returns Content-Type only" {
  let headers = auth_headers()
  inspect(headers.contains("Content-Type"), content="true")
  inspect(headers.contains("Authorization"), content="false")
}

///|
test "default_base_url is correct" {
  inspect(
    default_base_url(),
    content="https://generativelanguage.googleapis.com/v1beta",
  )
}
