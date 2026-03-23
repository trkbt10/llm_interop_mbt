///|
/// Focused transform_request / transform_response coverage for same-surface and Codex paths

///|
fn smoke_ctx() -> @types.TransformContext {
  @types.TransformContext::default()
}

///|
test "transform_request: OpenAI same-surface renames max_tokens field" {
  let body = "{\"model\":\"o1-mini\",\"messages\":[],\"max_tokens\":42}"
  let result = transform_request(body, OpenAI, OpenAI, "o1-mini", {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "max_completion_tokens": Number(max_tokens, ..), .. } => {
      assert_eq(max_tokens.to_int(), 42)
      assert_false(result.contains("\"max_tokens\""))
    }
    _ => fail("Expected renamed max token field")
  }
}

///|
test "transform_request: Anthropic same-surface injects default max_tokens" {
  let body = "{\"model\":\"claude\",\"messages\":[]}"
  let result = transform_request(body, Anthropic, Anthropic, "claude-sonnet", {
    max_tokens: 1024,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "max_tokens": Number(max_tokens, ..), .. } =>
      assert_eq(max_tokens.to_int(), 1024)
    _ => fail("Expected injected max_tokens")
  }
}

///|
test "transform_request: Gemini same-surface is passthrough" {
  let body = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Hi\"}]}]}"
  assert_eq(
    transform_request(body, Gemini, Gemini, "gemini-2.5-flash", smoke_ctx()),
    body,
  )
}

///|
test "transform_request: OpenAI same-surface keeps existing renamed max token field" {
  let body = "{\"model\":\"o1-mini\",\"messages\":[],\"max_tokens\":42,\"max_completion_tokens\":64}"
  assert_eq(
    transform_request(body, OpenAI, OpenAI, "o1-mini", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
    body,
  )
}

///|
test "transform_request: OpenAI to Codex extracts prompt and messages" {
  let body =
    #|{"model":"gpt-5-codex","messages":[{"role":"system","content":"Be terse"},{"role":"user","content":"Explain MoonBit"}],"reasoning_effort":"medium"}
  let result = transform_request(
    body,
    OpenAI,
    Codex,
    "gpt-5-codex",
    smoke_ctx(),
  )
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "prompt": String(prompt),
      "model": String(model),
      "effort": String(effort),
      "messages": Array(messages),
      ..
    } => {
      assert_true(prompt.contains("Be terse"))
      assert_true(prompt.contains("Explain MoonBit"))
      assert_eq(model, "gpt-5-codex")
      assert_eq(effort, "medium")
      assert_eq(messages.length(), 2)
    }
    _ => fail("Expected Codex protocol request")
  }
}

///|
test "transform_request: Codex to Anthropic is passthrough" {
  let body = "{\"prompt\":\"hello from codex\"}"
  assert_eq(
    transform_request(body, Codex, Anthropic, "ignored", smoke_ctx()),
    body,
  )
}

///|
test "transform_request: Anthropic to OpenAI and Codex pivot correctly" {
  let anthropic_body =
    #|{"model":"claude","system":"Be concise","messages":[{"role":"user","content":"Hi"}]}
  let openai = transform_request(
    anthropic_body,
    Anthropic,
    OpenAI,
    "claude-sonnet",
    smoke_ctx(),
  )
  let openai_json : Json = @json.parse(openai) catch {
    _ => fail("parse error")
  }
  match openai_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 2)
    _ => fail("Expected OpenAI chat request")
  }

  let codex = transform_request(
    anthropic_body,
    Anthropic,
    Codex,
    "claude-sonnet",
    smoke_ctx(),
  )
  let codex_json : Json = @json.parse(codex) catch { _ => fail("parse error") }
  match codex_json {
    { "prompt": String(prompt), .. } => assert_true(prompt.contains("Hi"))
    _ => fail("Expected Codex prompt")
  }
}

///|
test "transform_request: Gemini to Anthropic pivots through OpenAI" {
  let body =
    #|{"contents":[{"role":"user","parts":[{"text":"Hello Gemini"}]}]}
  let result = transform_request(
    body,
    Gemini,
    Anthropic,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let result_json : Json = @json.parse(result) catch {
    _ => fail("parse error")
  }
  match result_json {
    { "messages": [{ "role": String("user"), .. }], .. } => ()
    _ => fail("Expected Anthropic request")
  }
}

///|
test "transform_request: Gemini to OpenAI and Codex pivot correctly" {
  let body =
    #|{"contents":[{"role":"user","parts":[{"text":"Hello Gemini"}]}]}
  let openai = transform_request(
    body,
    Gemini,
    OpenAI,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let openai_json : Json = @json.parse(openai) catch {
    _ => fail("parse error")
  }
  match openai_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 1)
    _ => fail("Expected OpenAI chat request")
  }

  let codex = transform_request(
    body,
    Gemini,
    Codex,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let codex_json : Json = @json.parse(codex) catch { _ => fail("parse error") }
  match codex_json {
    { "prompt": String(prompt), .. } =>
      assert_true(prompt.contains("Hello Gemini"))
    _ => fail("Expected Codex prompt")
  }
}

///|
test "transform_request: Anthropic to Gemini and Codex to Codex are covered" {
  let anthropic_body =
    #|{"model":"claude","system":"Be concise","messages":[{"role":"user","content":"Hi"}]}
  let gemini = transform_request(
    anthropic_body,
    Anthropic,
    Gemini,
    "claude-sonnet",
    smoke_ctx(),
  )
  let gemini_json : Json = @json.parse(gemini) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    { "contents": Array(contents), .. } => assert_eq(contents.length(), 1)
    _ => fail("Expected Gemini request")
  }

  let codex_body = "{\"prompt\":\"hello from codex\"}"
  assert_eq(
    transform_request(codex_body, Codex, Codex, "ignored", smoke_ctx()),
    codex_body,
  )
}

///|
test "transform_request: non-object same-surface bodies stay unchanged" {
  let body = "[]"
  assert_eq(
    transform_request(body, OpenAI, OpenAI, "o1-mini", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
    body,
  )
  assert_eq(
    transform_request(body, Anthropic, Anthropic, "claude", {
      max_tokens: 128,
      max_tokens_field: "max_tokens",
    }),
    body,
  )
}

///|
test "transform_response: Anthropic error to Anthropic stays unchanged" {
  let body =
    #|{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}
  assert_eq(transform_response(body, Anthropic, Anthropic), body)
}

///|
test "transform_response: incomplete Anthropic error payload falls through as empty chat" {
  let body = "{\"type\":\"error\"}"
  let json : Json = @json.parse(transform_response(body, Anthropic, OpenAI)) catch {
    _ => fail("parse error")
  }
  match json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "")
    _ => fail("Expected empty chat completion fallback")
  }
}

///|
test "transform_response: Codex to OpenAI produces chat completion" {
  let body =
    #|[{"method":"item/agentMessage/delta","params":{"delta":"Hello from Codex"}},{"method":"turn/completed","params":{"turn":{"id":"turn_1","status":"completed"}}}]
  let result = transform_response(body, Codex, OpenAI)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "Hello from Codex")
    _ => fail("Expected OpenAI chat response")
  }
}

///|
test "transform_response: Codex to Anthropic and Gemini pivot through OpenAI" {
  let body =
    #|[{"method":"item/agentMessage/delta","params":{"delta":"Hello from Codex"}},{"method":"turn/completed","params":{"turn":{"id":"turn_1","status":"completed"}}}]
  let anthropic_json : Json = @json.parse(
    transform_response(body, Codex, Anthropic),
  ) catch {
    _ => fail("parse error")
  }
  match anthropic_json {
    { "content": [{ "type": String("text"), "text": String(text), .. }], .. } =>
      assert_eq(text, "Hello from Codex")
    _ => fail("Expected Anthropic response")
  }

  let gemini_json : Json = @json.parse(transform_response(body, Codex, Gemini)) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    { "candidates": Array(candidates), .. } => assert_eq(candidates.length(), 1)
    _ => fail("Expected Gemini response")
  }
}

///|
test "transform_response: success responses passthrough when targeting Codex" {
  let openai_body =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}]}
  assert_eq(transform_response(openai_body, OpenAI, Codex), openai_body)
}

///|
test "transform_response: Codex passthrough to Codex" {
  let body = "[{\"method\":\"turn/completed\",\"params\":{\"turn\":{\"id\":\"t\",\"status\":\"completed\"}}}]"
  assert_eq(transform_response(body, Codex, Codex), body)
}
