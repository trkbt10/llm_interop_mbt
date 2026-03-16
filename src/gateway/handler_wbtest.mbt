///|
/// Gateway routing and proxy preparation tests

///|
fn create_test_config() -> GatewayConfig {
  let openai_provider : ProviderConfig = {
    id: "openai",
    base_url: "https://api.openai.com/v1",
    api_key: "test-key",
    auth: ApiKey,
    api: OpenAICompletions,
    headers: {},
    auth_header: true,
    models: [ModelConfig::new("gpt-4o"), ModelConfig::new("gpt-4o-mini")],
    model_patterns: ["gpt-", "o1", "o3", "o4"],
  }
  let anthropic_provider : ProviderConfig = {
    id: "anthropic",
    base_url: "https://api.anthropic.com",
    api_key: "test-key",
    auth: ApiKey,
    api: AnthropicMessages,
    headers: {},
    auth_header: true,
    models: [ModelConfig::new("claude-sonnet-4-20250514")],
    model_patterns: ["claude-"],
  }
  let gemini_provider : ProviderConfig = {
    id: "gemini",
    base_url: "https://generativelanguage.googleapis.com/v1",
    api_key: "test-key",
    auth: ApiKey,
    api: GoogleGenerativeAI,
    headers: {},
    auth_header: true,
    models: [ModelConfig::new("gemini-pro")],
    model_patterns: ["gemini-"],
  }
  {
    mode: Merge,
    providers: {
      "openai": openai_provider,
      "anthropic": anthropic_provider,
      "gemini": gemini_provider,
    },
    backends: [],
    server: { port: 18080, host: "0.0.0.0" },
  }
}

// =============================================================================
// Gateway::resolve tests
// =============================================================================

///|
test "resolve: GET /health returns Health" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("GET", "/health", "") {
    Health => ()
    other => fail("expected Health, got \{other}")
  }
}

///|
test "resolve: GET / returns Health" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("GET", "/", "") {
    Health => ()
    other => fail("expected Health, got \{other}")
  }
}

///|
test "resolve: GET /v1/models returns ListModels" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("GET", "/v1/models", "") {
    ListModels => ()
    other => fail("expected ListModels, got \{other}")
  }
}

///|
test "resolve: POST /v1/chat/completions with OpenAI dialect" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  let body = #|{"model": "gpt-4o", "messages": []}
  match gw.resolve("POST", "/v1/chat/completions", body) {
    Completion(dialect=@chat.Dialect::OpenAI, ..) => ()
    other => fail("expected Completion(openai), got \{other}")
  }
}

///|
test "resolve: POST /v1/responses with OpenAI dialect" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  let body = #|{"model": "gpt-4o", "input": []}
  match gw.resolve("POST", "/v1/responses", body) {
    Completion(dialect=@chat.Dialect::OpenAI, ..) => ()
    other => fail("expected Completion(responses), got \{other}")
  }
}

///|
test "resolve: POST /v1/messages with Anthropic dialect" {
  let gw = Gateway::new(create_test_config(), Anthropic)
  let body = #|{"model": "claude-sonnet-4-20250514", "max_tokens": 100, "messages": []}
  match gw.resolve("POST", "/v1/messages", body) {
    Completion(dialect=@chat.Dialect::Anthropic, ..) => ()
    other => fail("expected Completion(anthropic), got \{other}")
  }
}

///|
test "resolve: POST /v1/messages returns NotFound for OpenAI dialect" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("POST", "/v1/messages", "{}") {
    NotFound(..) => ()
    other => fail("expected NotFound, got \{other}")
  }
}

///|
test "resolve: Gemini generateContent" {
  let gw = Gateway::new(create_test_config(), Gemini)
  let body = #|{"contents": [{"parts": [{"text": "hi"}]}]}
  match gw.resolve("POST", "/v1/models/gemini-pro:generateContent", body) {
    CompletionWithModel(dialect=@chat.Dialect::Gemini, model="gemini-pro", ..) => ()
    other => fail("expected CompletionWithModel(gemini), got \{other}")
  }
}

///|
test "resolve: Gemini path returns NotFound for OpenAI dialect" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("POST", "/v1/models/gemini-pro:generateContent", "{}") {
    NotFound(..) => ()
    other => fail("expected NotFound, got \{other}")
  }
}

///|
test "resolve: unknown path returns NotFound" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.resolve("GET", "/unknown/path", "") {
    NotFound(path="/unknown/path", dialect="openai") => ()
    other => fail("expected NotFound, got \{other}")
  }
}

// =============================================================================
// select_backend tests
// =============================================================================

///|
test "select_backend finds model in provider" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.select_backend("gpt-4o") {
    Some(b) => assert_eq(b.provider.id, "openai")
    None => fail("expected to find backend for gpt-4o")
  }
}

///|
test "select_backend finds anthropic model" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.select_backend("claude-sonnet-4-20250514") {
    Some(b) => assert_eq(b.provider.id, "anthropic")
    None => fail("expected to find backend for claude model")
  }
}

///|
test "select_backend prefix routing for unknown claude model" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.select_backend("claude-3-opus-20240229") {
    Some(b) => assert_eq(b.provider.id, "anthropic")
    None => fail("expected prefix routing to anthropic")
  }
}

///|
test "select_backend returns None for unknown model" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  match gw.select_backend("unknown-model-xyz") {
    None => ()
    Some(_) => fail("expected None for unknown model")
  }
}

// =============================================================================
// prepare_upstream tests
// =============================================================================

///|
test "prepare_upstream: OpenAI provider builds correct request" {
  let provider : ProviderConfig = {
    id: "openai",
    base_url: "https://api.openai.com/v1",
    api_key: "sk-test",
    auth: ApiKey,
    api: OpenAICompletions,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let body = #|{"model": "gpt-4o", "messages": [{"role": "user", "content": "hi"}]}
  let req = prepare_upstream(
    provider, body, @chat.Dialect::OpenAI, "gpt-4o", "https://api.openai.com/v1", "sk-test",
  )
  assert_eq(req.origin, "https://api.openai.com")
  assert_eq(req.path, "/v1/chat/completions")
  assert_eq(req.headers.get("Authorization"), Some("Bearer sk-test"))
  assert_eq(req.headers.get("Content-Type"), Some("application/json"))
}

///|
test "prepare_upstream: Anthropic provider builds correct request" {
  let provider : ProviderConfig = {
    id: "anthropic",
    base_url: "https://api.anthropic.com",
    api_key: "sk-ant-test",
    auth: ApiKey,
    api: AnthropicMessages,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let body = #|{"model": "claude-sonnet-4-20250514", "messages": [{"role": "user", "content": "hi"}]}
  let req = prepare_upstream(
    provider, body, @chat.Dialect::OpenAI, "claude-sonnet-4-20250514", "https://api.anthropic.com", "sk-ant-test",
  )
  assert_eq(req.origin, "https://api.anthropic.com")
  assert_eq(req.path, "/messages")
  assert_eq(req.headers.get("x-api-key"), Some("sk-ant-test"))
  assert_eq(req.headers.get("anthropic-version"), Some("2023-06-01"))
  // Should NOT have Authorization header
  assert_eq(req.headers.get("Authorization"), None)
}

///|
test "prepare_upstream: Gemini provider puts key in URL" {
  let provider : ProviderConfig = {
    id: "gemini",
    base_url: "https://generativelanguage.googleapis.com/v1",
    api_key: "gemini-key",
    auth: ApiKey,
    api: GoogleGenerativeAI,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let body = #|{"model": "gemini-pro", "messages": [{"role": "user", "content": "hi"}]}
  let req = prepare_upstream(
    provider,
    body,
    @chat.Dialect::OpenAI,
    "gemini-pro",
    "https://generativelanguage.googleapis.com/v1",
    "gemini-key",
  )
  assert_eq(req.origin, "https://generativelanguage.googleapis.com")
  assert_true(req.path.contains("gemini-pro:generateContent"))
  assert_true(req.path.contains("key=gemini-key"))
  // Should NOT have Authorization header
  assert_eq(req.headers.get("Authorization"), None)
}

///|
test "prepare_upstream: cross-dialect transforms body" {
  let provider : ProviderConfig = {
    id: "anthropic",
    base_url: "https://api.anthropic.com",
    api_key: "key",
    auth: ApiKey,
    api: AnthropicMessages,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let body = #|{"model": "claude-sonnet-4-20250514", "messages": [{"role": "user", "content": "hello"}]}
  let req = prepare_upstream(
    provider, body, @chat.Dialect::OpenAI, "claude-sonnet-4-20250514", "https://api.anthropic.com", "key",
  )
  // Body should be transformed from OpenAI to Anthropic format
  let parsed = @json.parse(req.body) catch {
    _ => fail("failed to parse transformed body")
  }
  // Anthropic format should have max_tokens instead of choices
  match parsed {
    { "messages": Array(_), .. } => ()
    _ => fail("expected messages in transformed body")
  }
}

// =============================================================================
// prepare_models_request tests
// =============================================================================

///|
test "prepare_models_request: OpenAI provider" {
  let provider : ProviderConfig = {
    id: "openai",
    base_url: "",
    api_key: "",
    auth: ApiKey,
    api: OpenAICompletions,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let req = prepare_models_request(
    provider, "https://api.openai.com/v1", "sk-test",
  )
  assert_eq(req.path, "/v1/models")
  assert_eq(req.headers.get("Authorization"), Some("Bearer sk-test"))
}

///|
test "prepare_models_request: Anthropic provider" {
  let provider : ProviderConfig = {
    id: "anthropic",
    base_url: "",
    api_key: "",
    auth: ApiKey,
    api: AnthropicMessages,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
  let req = prepare_models_request(
    provider, "https://api.anthropic.com", "sk-ant-test",
  )
  assert_eq(req.path, "/models")
  assert_eq(req.headers.get("x-api-key"), Some("sk-ant-test"))
}

// =============================================================================
// parse_models_response tests
// =============================================================================

///|
test "parse_models_response: OpenAI format" {
  let response = #|{"data": [{"id": "gpt-4o"}, {"id": "gpt-4o-mini"}]}
  let models = parse_models_response(response, "openai")
  assert_eq(models.length(), 2)
  match models[0] {
    { "id": "gpt-4o", "owned_by": "openai", .. } => ()
    _ => fail("expected gpt-4o model")
  }
}

///|
test "parse_models_response: Anthropic format" {
  let response = #|{"models": [{"id": "claude-sonnet-4-20250514"}]}
  let models = parse_models_response(response, "anthropic")
  assert_eq(models.length(), 1)
  match models[0] {
    { "id": "claude-sonnet-4-20250514", "owned_by": "anthropic", .. } => ()
    _ => fail("expected claude model")
  }
}

///|
test "parse_models_response: invalid JSON returns empty" {
  let models = parse_models_response("not json", "test")
  assert_eq(models.length(), 0)
}

// =============================================================================
// Helper function tests
// =============================================================================

///|
test "extract_json_field: valid body" {
  let body = #|{"model": "gpt-4o", "messages": []}
  match @utils.extract_json_field(body, "model") {
    Some("gpt-4o") => ()
    other => fail("expected Some(gpt-4o), got \{other}")
  }
}

///|
test "extract_json_field: missing field" {
  let body = #|{"messages": []}
  match @utils.extract_json_field(body, "model") {
    None => ()
    other => fail("expected None, got \{other}")
  }
}

///|
test "extract_json_field: invalid JSON" {
  match @utils.extract_json_field("not json", "model") {
    None => ()
    other => fail("expected None, got \{other}")
  }
}

///|
test "inject_json_field: adds field when missing" {
  let body = #|{"messages": []}
  let result = @utils.inject_json_field(body, "model", "gpt-4o")
  let json = @json.parse(result) catch {
    _ => fail("failed to parse result")
  }
  match json {
    { "model": "gpt-4o", .. } => ()
    _ => fail("expected model field")
  }
}

///|
test "inject_json_field: preserves existing field" {
  let body = #|{"model": "existing", "messages": []}
  let result = @utils.inject_json_field(body, "model", "gpt-4o")
  let json = @json.parse(result) catch {
    _ => fail("failed to parse result")
  }
  match json {
    { "model": "existing", .. } => ()
    _ => fail("expected original model preserved")
  }
}

///|
test "list_configured_models returns all models" {
  let gw = Gateway::new(create_test_config(), OpenAI)
  let models = gw.list_configured_models()
  assert_true(models.length() >= 3)
  let ids : Array[String] = []
  for m in models {
    match m {
      { "id": String(id), .. } => ids.push(id)
      _ => ()
    }
  }
  assert_true(ids.contains("gpt-4o"))
  assert_true(ids.contains("claude-sonnet-4-20250514"))
  assert_true(ids.contains("gemini-pro"))
}

///|
test "extract_model_from_path extracts model correctly" {
  assert_eq(extract_model_from_path("/v1/models/gemini-pro:generateContent"), "gemini-pro")
}

///|
test "extract_model_from_path handles complex model names" {
  assert_eq(
    extract_model_from_path("/v1/models/gemini-1.5-pro-latest:generateContent"),
    "gemini-1.5-pro-latest",
  )
}

// =============================================================================
// HttpResponse / CORS tests
// =============================================================================

///|
test "HttpResponse::error creates proper error structure" {
  let resp = HttpResponse::error(500, "test error")
  assert_eq(resp.status, 500)
  let body = @json.parse(resp.body) catch {
    _ => fail("failed to parse response body")
  }
  match body {
    { "error": { "message": "test error", .. }, .. } => ()
    _ => fail("expected error structure")
  }
}

///|
test "add_cors_headers adds required headers" {
  let resp = HttpResponse::ok({ "test": true })
  let with_cors = add_cors_headers(resp)
  match with_cors.headers.get("Access-Control-Allow-Origin") {
    Some(origin) => assert_eq(origin, "*")
    None => fail("expected Access-Control-Allow-Origin header")
  }
  match with_cors.headers.get("Access-Control-Allow-Methods") {
    Some(methods) => assert_true(methods.contains("POST"))
    None => fail("expected Access-Control-Allow-Methods header")
  }
}
