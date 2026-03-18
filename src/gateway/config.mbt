///|
/// Gateway configuration parser

///|
/// Default port for the gateway server
let default_server_port : Int = 18080

///|
/// Parse gateway configuration from JSON
pub fn parse_config(json : Json) -> GatewayConfig raise GatewayError {
  let mode = parse_mode(json)
  let providers = parse_providers(json)
  let server = parse_server(json)
  { mode, providers, server }
}

///|
fn parse_mode(json : Json) -> ConfigMode {
  match json {
    { "mode": String(s), .. } =>
      match s.to_lower() {
        "replace" => Replace
        _ => Merge
      }
    _ => Merge
  }
}

///|
fn parse_providers(
  json : Json,
) -> Map[String, ProviderConfig] raise GatewayError {
  let result : Map[String, ProviderConfig] = {}
  match json {
    { "providers": Object(obj), .. } =>
      for id, prov_json in obj {
        result[id] = parse_provider(id, prov_json)
      }
    _ => ()
  }
  result
}

///|
fn parse_provider(
  id : String,
  json : Json,
) -> ProviderConfig raise GatewayError {
  let base_url = match json {
    { "baseUrl": String(s), .. } => s
    { "baseURL": String(s), .. } => s
    _ => ""
  }
  let api_key = match json {
    { "apiKey": String(s), .. } => s
    _ => ""
  }
  let auth = match json {
    { "auth": String(s), .. } => AuthMode::from_string(s).unwrap_or(ApiKey)
    _ => ApiKey
  }
  let api = match json {
    { "api": String(s), .. } =>
      match ModelApi::from_string(s) {
        Some(a) => a
        None => raise GatewayError::ConfigError("Unknown api: " + s)
      }
    _ => OpenAICompletions
  }
  let headers = parse_string_map(json, "headers")
  let auth_header = match json {
    { "authHeader": False, .. } => false
    _ => true
  }
  let models = parse_models(json)
  let models_from_endpoint = match json {
    { "modelsFromEndpoint": False, .. } => false
    _ => true
  }
  let model_patterns = parse_string_array(json, "modelPatterns")
  let codex = parse_codex_config(json)
  let claude_mcp = parse_claude_mcp_config(json)
  let model_aliases = parse_string_map(json, "modelAliases")
  {
    id,
    base_url,
    api_key,
    auth,
    api,
    headers,
    auth_header,
    models,
    models_from_endpoint,
    model_patterns,
    codex,
    claude_mcp,
    model_aliases,
  }
}

///|
/// Parse optional Codex app-server configuration from provider JSON.
fn parse_codex_config(json : Json) -> @codex.CodexConfig? {
  match json {
    { "codex": Object(obj), .. } => {
      let defaults = @codex.CodexConfig::default()
      Some({
        command: obj_string(obj, "command", defaults.command),
        approval_policy: obj_opt_string(
          obj,
          "approvalPolicy",
          defaults.approval_policy,
        ),
        thread_sandbox: obj_opt_string(
          obj,
          "threadSandbox",
          defaults.thread_sandbox,
        ),
        turn_sandbox_policy: obj_opt_string(
          obj,
          "turnSandboxPolicy",
          defaults.turn_sandbox_policy,
        ),
        turn_timeout_ms: obj_int(obj, "turnTimeoutMs", defaults.turn_timeout_ms),
        read_timeout_ms: obj_int(obj, "readTimeoutMs", defaults.read_timeout_ms),
        stall_timeout_ms: obj_int(
          obj,
          "stallTimeoutMs",
          defaults.stall_timeout_ms,
        ),
      })
    }
    _ => None
  }
}

///|
/// Parse optional `claude mcp serve` configuration from provider JSON.
fn parse_claude_mcp_config(json : Json) -> @claude_mcp.ClaudeMcpConfig? {
  match json {
    { "claudeMcp": Object(obj), .. } => {
      let defaults = @claude_mcp.ClaudeMcpConfig::default()
      Some({
        command: obj_string(obj, "command", defaults.command),
        args: obj_string_array(obj, "args", defaults.args),
        env: obj_string_map(obj, "env", defaults.env),
        timeout_ms: obj_int(obj, "timeoutMs", defaults.timeout_ms),
      })
    }
    _ => None
  }
}

// =============================================================================
// JSON field extraction helpers — eliminate repeated match patterns
// =============================================================================

///|
/// Extract a String→String map from a top-level JSON field
fn parse_string_map(json : Json, key : String) -> Map[String, String] {
  let result : Map[String, String] = {}
  let obj : Map[String, Json]? = match (key, json) {
    ("headers", { "headers": Object(o), .. }) => Some(o)
    ("modelAliases", { "modelAliases": Object(o), .. }) => Some(o)
    _ => None
  }
  match obj {
    Some(o) =>
      for k, v in o {
        match v {
          String(s) => result[k] = s
          _ => ()
        }
      }
    None => ()
  }
  result
}

///|
/// Extract a string array from a top-level JSON field
fn parse_string_array(json : Json, key : String) -> Array[String] {
  let arr : Array[Json]? = match (key, json) {
    ("modelPatterns", { "modelPatterns": Array(a), .. }) => Some(a)
    _ => None
  }
  match arr {
    Some(a) => {
      let result : Array[String] = []
      for v in a {
        match v {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    None => []
  }
}

///|
/// Get string from object field with default
fn obj_string(
  obj : Map[String, Json],
  key : String,
  default : String,
) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => default
  }
}

///|
/// Get optional string from object field with default
fn obj_opt_string(
  obj : Map[String, Json],
  key : String,
  default : String?,
) -> String? {
  match obj.get(key) {
    Some(String(s)) => Some(s)
    _ => default
  }
}

///|
/// Get int from object field with default
fn obj_int(obj : Map[String, Json], key : String, default : Int) -> Int {
  match obj.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => default
  }
}

///|
/// Get double from object field with default
fn obj_double(
  obj : Map[String, Json],
  key : String,
  default : Double,
) -> Double {
  match obj.get(key) {
    Some(Number(n, ..)) => n
    _ => default
  }
}

///|
/// Get bool from object field (defaults to false)
fn obj_bool(obj : Map[String, Json], key : String) -> Bool {
  match obj.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
/// Get string array from object field with default
fn obj_string_array(
  obj : Map[String, Json],
  key : String,
  default : Array[String],
) -> Array[String] {
  match obj.get(key) {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for v in arr {
        match v {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    _ => default
  }
}

///|
/// Get string map from object field with default
fn obj_string_map(
  obj : Map[String, Json],
  key : String,
  default : Map[String, String],
) -> Map[String, String] {
  match obj.get(key) {
    Some(Object(e)) => {
      let result : Map[String, String] = {}
      for k, v in e {
        match v {
          String(s) => result[k] = s
          _ => ()
        }
      }
      result
    }
    _ => default
  }
}

// =============================================================================
// Model parsing
// =============================================================================

///|
fn parse_models(json : Json) -> Array[ModelConfig] raise GatewayError {
  let result : Array[ModelConfig] = []
  match json {
    { "models": Array(arr), .. } =>
      for m in arr {
        result.push(parse_model(m))
      }
    _ => ()
  }
  result
}

///|
fn parse_model(json : Json) -> ModelConfig raise GatewayError {
  let id = match json {
    { "id": String(s), .. } => s
    _ => raise GatewayError::ConfigError("model.id is required")
  }
  let name = match json {
    { "name": String(s), .. } => s
    _ => id
  }
  let api = match json {
    { "api": String(s), .. } => ModelApi::from_string(s)
    _ => None
  }
  let reasoning = match json {
    { "reasoning": True, .. } => true
    _ => false
  }
  let input = parse_input_modalities(json)
  let cost = parse_cost(json)
  let context_window = match json {
    { "contextWindow": Number(n, ..), .. } => n.to_int()
    _ => 128000
  }
  let max_tokens = match json {
    { "maxTokens": Number(n, ..), .. } => n.to_int()
    _ => 4096
  }
  let headers = parse_string_map(json, "headers")
  let compat = parse_compat(json)
  {
    id,
    name,
    api,
    reasoning,
    input,
    cost,
    context_window,
    max_tokens,
    headers,
    compat,
  }
}

///|
fn parse_input_modalities(json : Json) -> Array[InputModality] {
  let result : Array[InputModality] = []
  match json {
    { "input": Array(arr), .. } =>
      for v in arr {
        match v {
          String("text") => result.push(Text)
          String("image") => result.push(Image)
          _ => ()
        }
      }
    _ => result.push(Text)
  }
  if result.is_empty() {
    result.push(Text)
  }
  result
}

///|
fn parse_cost(json : Json) -> TokenCost {
  match json {
    { "cost": Object(obj), .. } =>
      {
        input: obj_double(obj, "input", 0.0),
        output: obj_double(obj, "output", 0.0),
        cache_read: obj_double(obj, "cacheRead", 0.0),
        cache_write: obj_double(obj, "cacheWrite", 0.0),
      }
    _ => TokenCost::default()
  }
}

///|
fn parse_compat(json : Json) -> ModelCompatConfig {
  match json {
    { "compat": Object(obj), .. } =>
      {
        supports_store: obj_bool(obj, "supportsStore"),
        supports_developer_role: obj_bool(obj, "supportsDeveloperRole"),
        supports_reasoning_effort: obj_bool(obj, "supportsReasoningEffort"),
        supports_usage_in_streaming: obj_bool(obj, "supportsUsageInStreaming"),
        supports_strict_mode: obj_bool(obj, "supportsStrictMode"),
        max_tokens_field: obj_string(obj, "maxTokensField", "max_tokens"),
        thinking_format: obj_string(obj, "thinkingFormat", ""),
        requires_tool_result_name: obj_bool(obj, "requiresToolResultName"),
        requires_assistant_after_tool_result: obj_bool(
          obj, "requiresAssistantAfterToolResult",
        ),
        requires_thinking_as_text: obj_bool(obj, "requiresThinkingAsText"),
        requires_mistral_tool_ids: obj_bool(obj, "requiresMistralToolIds"),
      }
    _ => ModelCompatConfig::default()
  }
}

// =============================================================================
// Server config & serialization
// =============================================================================

///|
fn parse_server(json : Json) -> ServerConfig {
  match json {
    { "server": Object(obj), .. } =>
      {
        port: obj_int(obj, "port", default_server_port),
        host: obj_string(obj, "host", "0.0.0.0"),
      }
    _ => { port: default_server_port, host: "0.0.0.0" }
  }
}

///|
/// Serialize config to JSON
pub fn config_to_json(config : GatewayConfig) -> Json {
  let obj : Map[String, Json] = {}
  // Providers
  if not(config.providers.is_empty()) {
    let providers : Map[String, Json] = {}
    for id, prov in config.providers {
      providers[id] = provider_to_json(prov)
    }
    obj["providers"] = Json::object(providers)
  }
  // Server
  let server : Map[String, Json] = {}
  server["port"] = Json::number(config.server.port.to_double())
  server["host"] = Json::string(config.server.host)
  obj["server"] = Json::object(server)
  Json::object(obj)
}

///|
fn provider_to_json(p : ProviderConfig) -> Json {
  let obj : Map[String, Json] = {}
  obj["baseUrl"] = Json::string(p.base_url)
  obj["api"] = Json::string(p.api.to_string())
  if not(p.models.is_empty()) {
    obj["models"] = Json::array(p.models.map(fn(m) { model_to_json(m) }))
  }
  Json::object(obj)
}

///|
fn model_to_json(m : ModelConfig) -> Json {
  let obj : Map[String, Json] = {}
  obj["id"] = Json::string(m.id)
  obj["name"] = Json::string(m.name)
  obj["contextWindow"] = Json::number(m.context_window.to_double())
  obj["maxTokens"] = Json::number(m.max_tokens.to_double())
  Json::object(obj)
}
