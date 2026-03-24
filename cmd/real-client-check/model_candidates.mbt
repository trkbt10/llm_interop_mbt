fn provider(
  id : String,
  api : @gateway.ModelApi,
  api_key : String,
  base_url : String,
) -> @gateway.ProviderConfig {
  {
    ..@gateway.ProviderConfig::new(id, api),
    api_key,
    base_url,
  }
}

///|
fn openai_stream_candidates() -> Array[String] {
  let selected_model = env("OPENAI_REALCHECK_MODEL")
  if selected_model != "" {
    [selected_model, "gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
  } else {
    ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
  }
}

///|
fn push_unique(values : Array[String], value : String) -> Unit {
  if value != "" && not(values.contains(value)) {
    values.push(value)
  }
}

///|
fn default_anthropic_candidates() -> Array[String] {
  [
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-opus-4-1-20250805",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
  ]
}

///|
fn append_default_anthropic_candidates(candidates : Array[String]) -> Unit {
  for model in default_anthropic_candidates() {
    push_unique(candidates, model)
  }
}

///|
async fn anthropic_candidates(api_key : String) -> Array[String] {
  let candidates : Array[String] = []
  push_unique(candidates, env("ANTHROPIC_REALCHECK_MODEL"))
  let client = @http.Client::new("https://api.anthropic.com") catch {
    _ => {
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let response = @async.with_timeout(request_timeout_ms, () => {
    client.get(
      "/v1/models",
      extra_headers={
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
      },
    )
  }) catch {
    _ => {
      client.close()
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let response_body = @io.Reader::read_all(client) catch {
    _ => {
      client.close()
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let text = response_body.text() catch { _ => "" }
  client.close()
  if response.code == 200 {
    let json : Json = @json.parse(text) catch {
      _ => {
        append_default_anthropic_candidates(candidates)
        return candidates
      }
    }
    match json {
      { "data": Array(items), .. } =>
        for item in items {
          match item {
            {
              "id": String(id),
              "capabilities": {
                "structured_outputs": { "supported": True, .. },
                ..
              },
              ..
            } => push_unique(candidates, id)
            _ => ()
          }
        }
      _ => ()
    }
  }
  append_default_anthropic_candidates(candidates)
  candidates
}

///|
fn gemini_candidates() -> Array[String] {
  let selected_model = env("GEMINI_REALCHECK_MODEL")
  if selected_model != "" {
    [
      selected_model,
      "gemini-2.0-flash",
      "gemini-2.5-flash-lite",
      "gemini-2.5-flash",
      "gemini-2.0-flash-001",
    ]
  } else {
    [
      "gemini-2.0-flash",
      "gemini-2.5-flash-lite",
      "gemini-2.5-flash",
      "gemini-2.0-flash-001",
    ]
  }
}

///|
fn groq_candidates() -> Array[String] {
  let selected_model = env("GROQ_REALCHECK_MODEL")
  if selected_model != "" {
    [selected_model, "openai/gpt-oss-20b", "llama-3.3-70b-versatile"]
  } else {
    ["openai/gpt-oss-20b", "llama-3.3-70b-versatile"]
  }
}

///|
fn is_retryable_model_error(code : Int, message : String) -> Bool {
  let lower = message.to_lower()
  if code == 429 {
    lower.contains("resource exhausted") ||
    lower.contains("rate limit") ||
    lower.contains("quota") ||
    lower.contains("try again later")
  } else {
    (code == 400 || code == 404 || code == 422) &&
    (
      lower.contains("model") ||
      lower.contains("does not support") ||
      lower.contains("output format") ||
      lower.contains("unsupported") ||
      lower.contains("not found") ||
      lower.contains("does not exist")
    )
  }
}

///|
