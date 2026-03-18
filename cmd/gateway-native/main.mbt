///|
/// LLM Gateway CLI - Native HTTP Server
///
/// Thin entry point: CLI parsing, env expansion, HTTP transport, server lifecycle.
/// All gateway logic (routing, transformation, preparation) lives in src/gateway/.

///|
let default_port : Int = 18080

///|
let default_host : String = "0.0.0.0"

///|
let default_config : String = "gateway-config.json"

///|
struct CliOptions {
  config_path : String
  host : String
  port : Int
  dialect : @gw.GatewaySurface
  help : Bool
}

///|
fn CliOptions::default() -> CliOptions {
  {
    config_path: default_config,
    host: default_host,
    port: default_port,
    dialect: @gw.GatewaySurface::OpenAI,
    help: false,
  }
}

///|
fn parse_args(args : Array[String]) -> CliOptions {
  let opts = CliOptions::default()
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      return { ..opts, help: true }
    } else if arg == "--config" || arg == "-c" {
      i = i + 1
      if i < args.length() {
        return {
          ..parse_args_from(args, i + 1, { ..opts, config_path: args[i] })
        }
      }
    } else if arg == "--host" {
      i = i + 1
      if i < args.length() {
        return { ..parse_args_from(args, i + 1, { ..opts, host: args[i] }) }
      }
    } else if arg == "--port" || arg == "-p" {
      i = i + 1
      if i < args.length() {
        let port = @strconv.parse_int(args[i]) catch { _ => opts.port }
        return { ..parse_args_from(args, i + 1, { ..opts, port, }) }
      }
    } else if arg == "--dialect" || arg == "-d" {
      i = i + 1
      if i < args.length() {
        let dialect = @gw.GatewaySurface::from_string(args[i]).unwrap_or(
          @gw.GatewaySurface::OpenAI,
        )
        return { ..parse_args_from(args, i + 1, { ..opts, dialect, }) }
      }
    }
    i = i + 1
  }
  opts
}

///|
fn parse_args_from(
  args : Array[String],
  start : Int,
  opts : CliOptions,
) -> CliOptions {
  let mut result = opts
  let mut i = start
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      return { ..result, help: true }
    } else if arg == "--config" || arg == "-c" {
      i = i + 1
      if i < args.length() {
        result = { ..result, config_path: args[i] }
      }
    } else if arg == "--host" {
      i = i + 1
      if i < args.length() {
        result = { ..result, host: args[i] }
      }
    } else if arg == "--port" || arg == "-p" {
      i = i + 1
      if i < args.length() {
        let port = @strconv.parse_int(args[i]) catch { _ => result.port }
        result = { ..result, port, }
      }
    } else if arg == "--dialect" || arg == "-d" {
      i = i + 1
      if i < args.length() {
        let dialect = @gw.GatewaySurface::from_string(args[i]).unwrap_or(
          result.dialect,
        )
        result = { ..result, dialect, }
      }
    }
    i = i + 1
  }
  result
}

///|
fn print_help() -> Unit {
  println(
    "LLM Gateway - OpenAI-compatible API proxy\n\nUsage: gateway [options]\n\nOptions:\n  -c, --config <path>    Path to config file (default: \{default_config})\n  -p, --port <number>    Port to listen on (default: \{default_port})\n      --host <host>      Host to bind (default: \{default_host})\n  -d, --dialect <type>   API dialect: openai, anthropic (default: openai)\n  -h, --help             Show this help message",
  )
}

///|
fn load_config(path : String) -> @gw.GatewayConfig raise @gw.GatewayError {
  let text = @fs.read_file_to_string(path) catch {
    _ => raise @gw.GatewayError::ConfigError("Failed to read config: " + path)
  }
  let json = @json.parse(text) catch {
    _ => raise @gw.GatewayError::ConfigError("Invalid JSON in config")
  }
  @gw.parse_config(json)
}

///|
/// Expand environment variables in a string (e.g., "${OPENAI_API_KEY}")
fn expand_env(s : String) -> String {
  if s.has_prefix("${") && s.has_suffix("}") && s.length() > 3 {
    let buf = StringBuilder::new()
    for i = 2; i < s.length() - 1; i = i + 1 {
      buf.write_char(Int::unsafe_to_char(s[i].to_int()))
    }
    let var_name = buf.to_string()
    @sys.get_env_var(var_name).unwrap_or("")
  } else {
    s
  }
}

// =============================================================================
// Request handling - dispatch via Gateway::resolve
// =============================================================================

///|
async fn handle_request(
  gateway : @gw.Gateway,
  meth : String,
  path : String,
  body : String,
) -> @gw.HttpResponse {
  match gateway.resolve(meth, path, body) {
    @gw.RouteResult::Health =>
      @gw.HttpResponse::ok({
        "status": "ok",
        "dialect": gateway.dialect.to_string(),
      })
    @gw.RouteResult::ListModels => proxy_list_models(gateway)
    @gw.RouteResult::Completion(dialect~, body~) => {
      let model = match @utils.extract_json_field(body, "model") {
        Some(m) => m
        None => return @gw.HttpResponse::error(400, "model field is required")
      }
      proxy_to_backend(gateway, body, dialect, model)
    }
    @gw.RouteResult::ResponsesApi(body~) => {
      let model = match @utils.extract_json_field(body, "model") {
        Some(m) => m
        None => return @gw.HttpResponse::error(400, "model field is required")
      }
      proxy_responses_api(gateway, body, model)
    }
    @gw.RouteResult::CompletionWithModel(dialect~, model~, body~) =>
      proxy_to_backend(gateway, @utils.inject_json_field(body, "model", model), dialect, model)
    @gw.RouteResult::NotFound(path~, dialect~) =>
      @gw.HttpResponse::error(
        404,
        "Not found: " + path + " (dialect: " + dialect + ")",
      )
  }
}

///|
/// Common: select backend, prepare upstream, send HTTP, return raw result.
async fn send_to_backend(
  gateway : @gw.Gateway,
  model : String,
  body : String,
  dialect : @gw.GatewaySurface,
) -> (@gw.ProviderConfig, Int, String) raise {
  let provider = match gateway.select_backend(model) {
    Some(p) => p
    None => raise @gw.GatewayError::BackendNotFound(model)
  }
  let base_url = expand_env(provider.base_url)
  let api_key = expand_env(provider.api_key)
  let upstream = @gw.prepare_upstream(
    provider, body, dialect, model, base_url, api_key,
  )
  let (status, response_text) = http_post(upstream)
  (provider, status, response_text)
}

///|
/// Proxy a completion request (Chat Completions / Messages / generateContent).
async fn proxy_to_backend(
  gateway : @gw.Gateway,
  body : String,
  target_dialect : @gw.GatewaySurface,
  model : String,
) -> @gw.HttpResponse {
  // Check if this model routes to a Codex backend
  let provider = match gateway.select_backend(model) {
    Some(p) => p
    None =>
      return @gw.HttpResponse::error(
        503, "No backend available for model: " + model,
      )
  }
  if provider.api.to_dialect() == @gw.GatewaySurface::Codex {
    return proxy_to_codex_backend(gateway, body, target_dialect, model, provider)
  }
  if provider.api == @gw.ModelApi::ClaudeMcpServe {
    return proxy_to_claude_mcp_backend(gateway, body, target_dialect, model, provider)
  }
  // Standard HTTP path
  let (provider, status, response_text) = try {
    send_to_backend(gateway, model, body, target_dialect)
  } catch {
    @gw.GatewayError::BackendNotFound(m) =>
      return @gw.HttpResponse::error(503, "No backend available for model: " + m)
    e => return @gw.HttpResponse::error(502, e.to_string())
  }
  let final_body = @gw.transform_response(
    response_text,
    provider.api.to_dialect(),
    target_dialect,
  )
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  { status, headers, body: final_body }
}

///|
/// Proxy a Responses API request via the harmony pipeline:
///   request(Responses API) → harmony → upstream(Chat Completions)
///   response(Chat Completions) → parse → harmony → response(Responses API)
async fn proxy_responses_api(
  gateway : @gw.Gateway,
  body : String,
  model : String,
) -> @gw.HttpResponse {
  let request_json = try { @json.parse(body) } catch { _ => Json::object({}) }
  let chat_body = @harmony.responses_request_to_chat_completions(request_json, stream=false).stringify()
  let (_provider, status, response_text) = try {
    send_to_backend(gateway, model, chat_body, @gw.GatewaySurface::OpenAI)
  } catch {
    @gw.GatewayError::BackendNotFound(m) =>
      return @gw.HttpResponse::error(503, "No backend available for model: " + m)
    e => return @gw.HttpResponse::error(502, e.to_string())
  }
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  if status >= 400 {
    return { status, headers, body: response_text }
  }
  let response_json = try { @json.parse(response_text) } catch { _ => Json::object({}) }
  let model_response = @openai.parse_openai_chat_response(response_json)
  let response_id : String = match response_json {
    { "id": String(id), .. } => id
    _ => "resp_" + model
  }
  let result = @harmony.model_response_to_responses_json(
    model_response, response_id~, model~,
  )
  { status, headers, body: result.stringify() }
}

///|
/// Execute HTTP POST and return (status_code, response_body)
async fn http_post(req : @gw.UpstreamRequest) -> (Int, String) {
  let client = @http.Client::new(req.origin) catch {
    e => return (502, "{\"error\":{\"message\":\"Failed to connect: \{e}\"}}")
  }
  let response = client.post(req.path, req.body, extra_headers=req.headers) catch {
    e => {
      client.close()
      return (502, "{\"error\":{\"message\":\"Request failed: \{e}\"}}")
    }
  }
  let response_body = @io.Reader::read_all(client) catch {
    e => {
      client.close()
      return (502, "{\"error\":{\"message\":\"Failed to read response: \{e}\"}}")
    }
  }
  let text = response_body.text() catch { _ => "" }
  client.close()
  (response.code, text)
}

///|
/// Fetch and aggregate models from all providers
async fn proxy_list_models(gateway : @gw.Gateway) -> @gw.HttpResponse {
  let all_models : Array[Json] = []
  let errors : Array[String] = []
  for _, provider in gateway.config.providers {
    // Codex app-server: query model/list via JSON-RPC subprocess
    if provider.api == @gw.ModelApi::CodexAppServer {
      let codex_models = fetch_codex_model_list(provider)
      for m in codex_models {
        all_models.push(m)
      }
      continue
    }
    // `claude mcp serve`: list configured models (tools exposed as single virtual model)
    if provider.api == @gw.ModelApi::ClaudeMcpServe {
      let claude_mcp_models = fetch_claude_mcp_model_list(provider)
      for m in claude_mcp_models {
        all_models.push(m)
      }
      continue
    }
    // Always include config-declared models
    let config_models = provider.list_model_json()
    for m in config_models {
      all_models.push(m)
    }
    // Optionally fetch remote models (default: true)
    if provider.models_from_endpoint {
      let base_url = expand_env(provider.base_url)
      let api_key = expand_env(provider.api_key)
      let upstream = @gw.prepare_models_request(provider, base_url, api_key)
      let (status, response_text) = http_get(upstream)
      if status != 200 {
        errors.push(
          "Provider \{provider.id} returned HTTP \{status}: \{response_text}",
        )
        continue
      }
      let models = @gw.parse_models_response(response_text, provider.id)
      for m in models {
        // Avoid duplicates with config models
        let is_dup = config_models.iter().any(fn(cm) {
          match cm {
            { "id": String(id), .. } => {
              match m {
                { "id": String(mid), .. } => id == mid
                _ => false
              }
            }
            _ => false
          }
        })
        if !is_dup {
          all_models.push(m)
        }
      }
    }
  }
  if errors.length() > 0 {
    let error_msg = errors.iter().fold(
      init="",
      fn(acc, e) {
        if acc == "" {
          e
        } else {
          acc + "; " + e
        }
      },
    )
    return @gw.HttpResponse::error(502, error_msg)
  }
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  let body : Json = { "object": "list", "data": Json::array(all_models) }
  { status: 200, headers, body: body.stringify() }
}

///|
/// Execute HTTP GET and return (status_code, response_body)
async fn http_get(req : @gw.UpstreamRequest) -> (Int, String) {
  let client = @http.Client::new(req.origin) catch {
    e => return (502, "{\"error\":{\"message\":\"Failed to connect: \{e}\"}}")
  }
  let response = client.get(req.path, extra_headers=req.headers) catch {
    e => {
      client.close()
      return (502, "{\"error\":{\"message\":\"Request failed: \{e}\"}}")
    }
  }
  let response_body = @io.Reader::read_all(client) catch {
    e => {
      client.close()
      return (502, "{\"error\":{\"message\":\"Failed to read response: \{e}\"}}")
    }
  }
  let text = response_body.text() catch { _ => "" }
  client.close()
  (response.code, text)
}

// =============================================================================
// Codex JSON-RPC stdio transport
// =============================================================================

///|
/// Per-provider Codex state: session + live subprocess channel
struct CodexBackendState {
  mut session : @codex.CodexSession
  mut channel : @ipc.IpcChannel?
}

///|
/// Mutable state for Codex providers, keyed by provider ID
let codex_backends : Map[String, CodexBackendState] = {}

///|
/// Spawn or reuse a Codex app-server subprocess for a provider.
async fn get_codex_channel(
  group : @async.TaskGroup[Unit],
  backend_id : String,
  command : String,
  cwd : String,
  api_key : String,
) -> @ipc.IpcChannel raise @gw.GatewayError {
  match codex_backends.get(backend_id) {
    Some(state) =>
      match state.channel {
        Some(ch) => return ch
        None => ()
      }
    None => ()
  }
  // Spawn a new codex app-server subprocess
  // Pass API key as environment variable if configured
  let env : Map[String, String] = {}
  if api_key != "" {
    env["OPENAI_API_KEY"] = api_key
  }
  let child = @subprocess.spawn_shell(
    group,
    command,
    cwd=cwd,
    env=env,
    pipe_stdin=true,
    pipe_stdout=true,
    pipe_stderr=true,
  ) catch {
    e =>
      raise @gw.GatewayError::NetworkError(
        "Failed to spawn codex app-server: " + e.to_string(),
      )
  }
  let channel = @ipc.IpcChannel::from_child(child)
  match codex_backends.get(backend_id) {
    Some(state) => state.channel = Some(channel)
    None => {
      let session = @codex.CodexSession::new(cwd)
      codex_backends[backend_id] = { session, channel: Some(channel) }
    }
  }
  channel
}

///|
/// Fetch model list from a Codex app-server subprocess via model/list JSON-RPC.
/// Uses dialect-layer step sequence from prepare_codex_model_list().
/// Returns empty array if subprocess is unavailable or fails.
async fn fetch_codex_model_list(provider : @gw.ProviderConfig) -> Array[Json] {
  let codex_cfg = match provider.codex {
    Some(cfg) => cfg
    None => return []
  }
  let cwd = if provider.base_url != "" {
    expand_env(provider.base_url)
  } else {
    "."
  }
  let session = @codex.CodexSession::new(cwd)
  let req = @codex.prepare_codex_model_list(session)
  let models : Array[Json] = []
  @async.with_task_group(async fn(group) {
    let api_key = expand_env(provider.api_key)
    let channel = get_codex_channel(
      group, provider.id + "_models", codex_cfg.command, cwd, api_key,
    ) catch {
      _ => {
        group.return_immediately(())
        return
      }
    }
    // Execute steps from dialect layer
    for step in req.steps {
      channel.send(step.message) catch {
        _ => { group.return_immediately(()); return }
      }
      match step.kind {
        @codex.Request => {
          let line = channel.recv() catch {
            _ => { group.return_immediately(()); return }
          }
          match line {
            Some(text) => {
              let json = @json.parse(text) catch { _ => continue }
              // Last request response is the model/list result
              match json {
                { "result": result, .. } => {
                  let parsed = @codex.parse_codex_model_list_result(
                    result, provider.id,
                  )
                  for m in parsed {
                    models.push(m)
                  }
                }
                _ => ()
              }
            }
            None => { group.return_immediately(()); return }
          }
        }
        @codex.Notification => continue
        _ => continue
      }
    }
    group.return_immediately(())
  })
  models
}

///|
/// Proxy a completion request to a Codex backend via stdio JSON-RPC.
async fn proxy_to_codex_backend(
  _gateway : @gw.Gateway,
  body : String,
  target_dialect : @gw.GatewaySurface,
  model : String,
  provider : @gw.ProviderConfig,
) -> @gw.HttpResponse {
  let codex_cfg = match provider.codex {
    Some(cfg) => cfg
    None => @codex.CodexConfig::default()
  }
  let cwd = if provider.base_url != "" {
    expand_env(provider.base_url)
  } else {
    "."
  }
  let command = codex_cfg.command
  let mut result : @gw.HttpResponse = @gw.HttpResponse::error(
    502, "Codex transport failed",
  )
  @async.with_task_group(async fn(group) {
    let api_key = expand_env(provider.api_key)
    let channel = get_codex_channel(
      group, provider.id, command, cwd, api_key,
    ) catch {
      e => {
        result = @gw.HttpResponse::error(502, e.to_string())
        group.return_immediately(())
        return
      }
    }
    let state = codex_backends[provider.id]
    let codex_body = @gw.transform_for_provider(
      provider,
      body,
      target_dialect,
      @gw.GatewaySurface::Codex,
      model,
    )
    let req = @codex.prepare_codex_upstream(codex_body, state.session)
    let (events_json, new_session) = codex_stdio_execute(
      channel, req.steps, req.next_session,
    )
    state.session = new_session
    let final_body = @gw.transform_response(
      events_json, @gw.GatewaySurface::Codex, target_dialect,
    )
    let headers : Map[String, String] = {}
    headers["Content-Type"] = "application/json"
    result = { status: 200, headers, body: final_body }
    group.return_immediately(())
  })
  result
}

///|
/// Execute Codex JSON-RPC steps over an IPC channel (stdio pipe).
/// Sends messages to stdin, reads responses/events from stdout.
async fn codex_stdio_execute(
  channel : @ipc.IpcChannel,
  steps : Array[@codex.CodexRpcStep],
  session : @codex.CodexSession,
) -> (String, @codex.CodexSession) {
  let mut current_session = session
  let events : Array[Json] = []
  for step in steps {
    let msg = match step.kind {
      TurnStart =>
        if current_session.thread_id != "" {
          @codex.patch_turn_start_thread_id(
            step.message, current_session.thread_id,
          )
        } else {
          step.message
        }
      _ => step.message
    }
    // Send the message
    channel.send(msg) catch {
      e =>
        return (
          @codex.codex_ipc_error_event("Codex send failed: " + e.to_string()),
          current_session,
        )
    }
    match step.kind {
      Notification =>
        // No response expected
        continue
      Request => {
        // Read a single JSON-RPC response line
        let line = channel.recv() catch {
          e =>
            return (
              @codex.codex_ipc_error_event("Codex recv failed: " + e.to_string()),
              current_session,
            )
        }
        match line {
          Some(text) => {
            let json = @json.parse(text) catch { _ => Json::null() }
            current_session = @codex.update_session_from_thread_response(
              current_session, json,
            )
            current_session = @codex.update_session_from_init_response(
              current_session, json,
            )
          }
          None =>
            return (
              @codex.codex_ipc_error_event("Codex EOF during setup"),
              current_session,
            )
        }
      }
      TurnStart => {
        // Read a single response for the turn/start request itself
        let first_line = channel.recv() catch {
          e =>
            return (
              @codex.codex_ipc_error_event("Codex recv failed: " + e.to_string()),
              current_session,
            )
        }
        match first_line {
          Some(text) => {
            let json = @json.parse(text) catch { _ => Json::null() }
            // Check for error response
            match json {
              { "error": _, .. } =>
                return (
                  "[" + text + "]",
                  current_session,
                )
              _ => ()
            }
          }
          None =>
            return (
              @codex.codex_ipc_error_event("Codex EOF on turn/start"),
              current_session,
            )
        }
        // Now read streaming events until turn/completed
        let mut turn_done = false
        while not(turn_done) {
          let line = channel.recv() catch { _ => break }
          match line {
            Some(text) => {
              let json = @json.parse(text) catch { _ => continue }
              events.push(json)
              // Check if this is turn/completed
              match json {
                { "method": String("turn/completed"), .. } =>
                  turn_done = true
                _ => ()
              }
            }
            None => break // EOF
          }
        }
        current_session = @codex.mark_session_turn_complete(current_session)
      }
    }
  }
  (Json::array(events).stringify(), current_session)
}

// =============================================================================
// `claude mcp serve` stdio transport
// =============================================================================

///|
/// Per-provider `claude mcp serve` state: session + live subprocess channel
struct ClaudeMcpBackendState {
  mut session : @claude_mcp.ClaudeMcpSession
  mut channel : @ipc.IpcChannel?
}

///|
/// Mutable state for `claude mcp serve` providers, keyed by provider ID
let claude_mcp_backends : Map[String, ClaudeMcpBackendState] = {}

///|
/// Spawn or reuse a `claude mcp serve` subprocess for a provider.
async fn get_claude_mcp_channel(
  group : @async.TaskGroup[Unit],
  backend_id : String,
  cfg : @claude_mcp.ClaudeMcpConfig,
) -> @ipc.IpcChannel raise @gw.GatewayError {
  match claude_mcp_backends.get(backend_id) {
    Some(state) =>
      match state.channel {
        Some(ch) => return ch
        None => ()
      }
    None => ()
  }
  // Build full command with shell-safe quoting
  let cmd = @spawn.Command::new(cfg.command)
  for arg in cfg.args {
    ignore(cmd.arg(arg))
  }
  let full_command = cmd.to_string()
  let child = @subprocess.spawn_shell(
    group,
    full_command,
    cwd=".",
    env=cfg.env,
    pipe_stdin=true,
    pipe_stdout=true,
    pipe_stderr=true,
  ) catch {
    e =>
      raise @gw.GatewayError::NetworkError(
        "Failed to spawn `claude mcp serve`: " + e.to_string(),
      )
  }
  let channel = @ipc.IpcChannel::from_child(child)
  match claude_mcp_backends.get(backend_id) {
    Some(state) => state.channel = Some(channel)
    None => {
      let session = @claude_mcp.ClaudeMcpSession::new()
      claude_mcp_backends[backend_id] = { session, channel: Some(channel) }
    }
  }
  channel
}

///|
/// List models from a `claude mcp serve` provider.
/// Tools are exposed as a single virtual model (or from configured models).
fn fetch_claude_mcp_model_list(provider : @gw.ProviderConfig) -> Array[Json] {
  if provider.models.length() > 0 {
    return provider.list_model_json()
  }
  [@gw.model_to_list_json("claude-code-tools", provider.id)]
}

///|
/// Proxy a completion request to a `claude mcp serve` backend via stdio.
async fn proxy_to_claude_mcp_backend(
  _gateway : @gw.Gateway,
  body : String,
  target_dialect : @gw.GatewaySurface,
  model : String,
  provider : @gw.ProviderConfig,
) -> @gw.HttpResponse {
  let cfg = match provider.claude_mcp {
    Some(c) => c
    None => @claude_mcp.ClaudeMcpConfig::default()
  }
  let mut result : @gw.HttpResponse = @gw.HttpResponse::error(
    502, "`claude mcp serve` transport failed",
  )
  @async.with_task_group(async fn(group) {
    let channel = get_claude_mcp_channel(group, provider.id, cfg) catch {
      e => {
        result = @gw.HttpResponse::error(502, e.to_string())
        group.return_immediately(())
        return
      }
    }
    let state = claude_mcp_backends[provider.id]
    // Transform request to OpenAI pivot first (if coming from another surface),
    // then extract prompt via claude_mcp dialect transform
    let openai_body = if target_dialect != @gw.GatewaySurface::OpenAI {
      @gw.transform_for_provider(
        provider, body, target_dialect, @gw.GatewaySurface::OpenAI, model,
      )
    } else {
      body
    }
    let ctx = @types.TransformContext::default()
    let intermediate = @claude_mcp.chat_request_to_prompt(openai_body, ctx)
    // Extract prompt from intermediate format
    let prompt_json = @json.parse(intermediate) catch { _ => Json::null() }
    let prompt = match prompt_json {
      { "prompt": String(p), .. } => p
      _ => intermediate
    }
    // Use Bash tool as default — send the prompt as a command
    let tool_name = "Bash"
    let arguments : Json = { "command": prompt }
    // Prepare tools/call steps (includes MCP init if needed)
    let req = @claude_mcp.prepare_tools_call(
      state.session, tool_name, arguments,
    )
    let (response_text, new_session) = claude_mcp_stdio_execute(
      channel, req.steps, req.next_session,
    )
    state.session = new_session
    // Transform result to OpenAI, then to target surface if needed
    let openai_response = @claude_mcp.tools_result_to_chat(response_text)
    let final_body = if target_dialect != @gw.GatewaySurface::OpenAI {
      @gw.transform_response(
        openai_response, @gw.GatewaySurface::OpenAI, target_dialect,
      )
    } else {
      openai_response
    }
    let headers : Map[String, String] = {}
    headers["Content-Type"] = "application/json"
    result = { status: 200, headers, body: final_body }
    group.return_immediately(())
  })
  result
}

///|
/// Execute MCP JSON-RPC steps over an IPC channel for `claude mcp serve`.
async fn claude_mcp_stdio_execute(
  channel : @ipc.IpcChannel,
  steps : Array[@jsonrpc.RpcStep],
  session : @claude_mcp.ClaudeMcpSession,
) -> (String, @claude_mcp.ClaudeMcpSession) {
  let current_session = session
  let mut last_response = ""
  for step in steps {
    channel.send(step.message) catch {
      e =>
        return (
          build_claude_mcp_error_response(
            "`claude mcp serve` send failed: " + e.to_string(),
          ),
          current_session,
        )
    }
    match step.kind {
      Notification => continue
      Request => {
        let line = channel.recv() catch {
          e =>
            return (
              build_claude_mcp_error_response(
                "`claude mcp serve` recv failed: " + e.to_string(),
              ),
              current_session,
            )
        }
        match line {
          Some(text) => last_response = text
          None =>
            return (
              build_claude_mcp_error_response(
                "`claude mcp serve` EOF during communication",
              ),
              current_session,
            )
        }
      }
    }
  }
  (last_response, current_session)
}

///|
/// Build an error response that tools_result_to_chat can handle
fn build_claude_mcp_error_response(message : String) -> String {
  let result : Map[String, Json] = {}
  let content : Array[Json] = [{ "type": "text", "text": message }]
  result["content"] = Json::array(content)
  result["isError"] = true.to_json()
  let obj : Map[String, Json] = {}
  obj["result"] = Json::object(result)
  Json::object(obj).stringify()
}

// =============================================================================
// Server lifecycle
// =============================================================================

///|
async fn run_server(gateway : @gw.Gateway, host : String, port : Int) -> Unit {
  let addr_str = host + ":" + port.to_string()
  let addr = @socket.Addr::parse(addr_str) catch {
    _ => {
      println("Failed to parse address: \{addr_str}")
      return
    }
  }
  let server = @http.Server::new(addr, reuse_addr=true) catch {
    e => {
      println("Failed to start server: \{e}")
      return
    }
  }
  println("Gateway listening on http://\{host}:\{port}")
  println("Dialect: \{gateway.dialect.to_string()}")
  println("Providers: \{gateway.config.providers.length()}")
  println("\nPress Ctrl+C to stop.\n")
  server.run_forever((req, body_reader, conn) => {
    let body_data = @io.Reader::read_all(body_reader) catch {
      _ => {
        conn.send_response(400, "Bad Request")
        conn.write("{\"error\":{\"message\":\"Failed to read body\"}}")
        conn.end_response()
        return
      }
    }
    let body_text = body_data.text() catch { _ => "" }
    let meth = match req.meth {
      @http.RequestMethod::Get => "GET"
      @http.RequestMethod::Post => "POST"
      @http.RequestMethod::Put => "PUT"
      @http.RequestMethod::Delete => "DELETE"
      @http.RequestMethod::Options => "OPTIONS"
      _ => "GET"
    }
    if meth == "OPTIONS" {
      let headers : Map[String, String] = {}
      headers["Access-Control-Allow-Origin"] = "*"
      headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
      headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      conn.send_response(204, "No Content", extra_headers=headers)
      conn.end_response()
      return
    }
    let response = handle_request(gateway, meth, req.path, body_text)
    let response_with_cors = @gw.add_cors_headers(response)
    conn.send_response(
      response_with_cors.status,
      "OK",
      extra_headers=response_with_cors.headers,
    )
    conn.write(response_with_cors.body)
    conn.end_response()
  })
}

///|
fn validate_config(config : @gw.GatewayConfig) -> Unit raise @gw.GatewayError {
  for provider_id, provider in config.providers {
    // Codex app-server and `claude mcp serve` don't require API key
    if provider.api == @gw.ModelApi::CodexAppServer ||
       provider.api == @gw.ModelApi::ClaudeMcpServe {
      continue
    }
    let api_key = expand_env(provider.api_key)
    if api_key == "" {
      raise @gw.GatewayError::ConfigError(
        "API key not set for provider '\{provider_id}'. Check environment variable in config.",
      )
    }
  }
}

///|
async fn main {
  let args = @sys.get_cli_args()
  let opts = parse_args(args)
  if opts.help {
    print_help()
    return
  }
  let base_config = load_config(opts.config_path) catch {
    e => {
      println("Error: \{e}")
      @sys.exit(1)
      return
    }
  }
  let config : @gw.GatewayConfig = {
    ..base_config,
    server: { host: opts.host, port: opts.port },
  }
  validate_config(config) catch {
    e => {
      println("Error: \{e}")
      @sys.exit(1)
      return
    }
  }
  let gateway = @gw.Gateway::new(config, opts.dialect)
  run_server(gateway, opts.host, opts.port)
}
