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
  let headers = parse_headers(json)
  let auth_header = match json {
    { "authHeader": False, .. } => false
    _ => true
  }
  let models = parse_models(json)
  let models_from_endpoint = match json {
    { "modelsFromEndpoint": False, .. } => false
    _ => true
  }
  let model_patterns = parse_model_patterns(json)
  let codex = parse_codex_config(json)
  let claude_mcp = parse_claude_mcp_config(json)
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
  }
}

///|
/// Parse optional Codex app-server configuration from provider JSON.
fn parse_codex_config(json : Json) -> @codex.CodexConfig? {
  match json {
    { "codex": Object(obj), .. } => {
      let defaults = @codex.CodexConfig::default()
      let command = match obj.get("command") {
        Some(String(s)) => s
        _ => defaults.command
      }
      let approval_policy = match obj.get("approvalPolicy") {
        Some(String(s)) => Some(s)
        _ => defaults.approval_policy
      }
      let thread_sandbox = match obj.get("threadSandbox") {
        Some(String(s)) => Some(s)
        _ => defaults.thread_sandbox
      }
      let turn_sandbox_policy = match obj.get("turnSandboxPolicy") {
        Some(String(s)) => Some(s)
        _ => defaults.turn_sandbox_policy
      }
      let turn_timeout_ms = match obj.get("turnTimeoutMs") {
        Some(Number(n, ..)) => n.to_int()
        _ => defaults.turn_timeout_ms
      }
      let read_timeout_ms = match obj.get("readTimeoutMs") {
        Some(Number(n, ..)) => n.to_int()
        _ => defaults.read_timeout_ms
      }
      let stall_timeout_ms = match obj.get("stallTimeoutMs") {
        Some(Number(n, ..)) => n.to_int()
        _ => defaults.stall_timeout_ms
      }
      Some({
        command,
        approval_policy,
        thread_sandbox,
        turn_sandbox_policy,
        turn_timeout_ms,
        read_timeout_ms,
        stall_timeout_ms,
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
      let command = match obj.get("command") {
        Some(String(s)) => s
        _ => defaults.command
      }
      let args : Array[String] = match obj.get("args") {
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
        _ => defaults.args
      }
      let env : Map[String, String] = match obj.get("env") {
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
        _ => defaults.env
      }
      let timeout_ms = match obj.get("timeoutMs") {
        Some(Number(n, ..)) => n.to_int()
        _ => defaults.timeout_ms
      }
      let tools : Array[String] = match obj.get("tools") {
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
        _ => defaults.tools
      }
      Some({ command, args, env, timeout_ms, tools })
    }
    _ => None
  }
}

///|
fn parse_headers(json : Json) -> Map[String, String] {
  let result : Map[String, String] = {}
  match json {
    { "headers": Object(obj), .. } =>
      for k, v in obj {
        match v {
          String(s) => result[k] = s
          _ => ()
        }
      }
    _ => ()
  }
  result
}

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
fn parse_model_patterns(json : Json) -> Array[String] {
  match json {
    { "modelPatterns": Array(arr), .. } => {
      let result : Array[String] = []
      for v in arr {
        match v {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
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
  let headers = parse_headers(json)
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
    { "cost": Object(obj), .. } => {
      let input = match obj.get("input") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      let output = match obj.get("output") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      let cache_read = match obj.get("cacheRead") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      let cache_write = match obj.get("cacheWrite") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      { input, output, cache_read, cache_write }
    }
    _ => TokenCost::default()
  }
}

///|
fn parse_compat(json : Json) -> ModelCompatConfig {
  match json {
    { "compat": Object(obj), .. } => {
      let supports_store = match obj.get("supportsStore") {
        Some(True) => true
        _ => false
      }
      let supports_developer_role = match obj.get("supportsDeveloperRole") {
        Some(True) => true
        _ => false
      }
      let supports_reasoning_effort = match obj.get("supportsReasoningEffort") {
        Some(True) => true
        _ => false
      }
      let supports_usage_in_streaming = match
        obj.get("supportsUsageInStreaming") {
        Some(True) => true
        _ => false
      }
      let supports_strict_mode = match obj.get("supportsStrictMode") {
        Some(True) => true
        _ => false
      }
      let max_tokens_field = match obj.get("maxTokensField") {
        Some(String(s)) => s
        _ => "max_tokens"
      }
      let thinking_format = match obj.get("thinkingFormat") {
        Some(String(s)) => s
        _ => ""
      }
      let requires_tool_result_name = match obj.get("requiresToolResultName") {
        Some(True) => true
        _ => false
      }
      let requires_assistant_after_tool_result = match
        obj.get("requiresAssistantAfterToolResult") {
        Some(True) => true
        _ => false
      }
      let requires_thinking_as_text = match obj.get("requiresThinkingAsText") {
        Some(True) => true
        _ => false
      }
      let requires_mistral_tool_ids = match obj.get("requiresMistralToolIds") {
        Some(True) => true
        _ => false
      }
      {
        supports_store,
        supports_developer_role,
        supports_reasoning_effort,
        supports_usage_in_streaming,
        supports_strict_mode,
        max_tokens_field,
        thinking_format,
        requires_tool_result_name,
        requires_assistant_after_tool_result,
        requires_thinking_as_text,
        requires_mistral_tool_ids,
      }
    }
    _ => ModelCompatConfig::default()
  }
}

///|
fn parse_server(json : Json) -> ServerConfig {
  match json {
    { "server": Object(obj), .. } => {
      let port = match obj.get("port") {
        Some(Number(n, ..)) => n.to_int()
        _ => default_server_port
      }
      let host = match obj.get("host") {
        Some(String(s)) => s
        _ => "0.0.0.0"
      }
      { port, host }
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
