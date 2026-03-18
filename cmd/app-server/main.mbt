///|
/// Codex app-server protocol frontend
///
/// Speaks JSON-RPC over stdio (JSONL) to Codex clients (VS Code, CLI).
/// Proxies requests to any LLM backend via the gateway transform pipeline.
///
/// ```
/// Codex client (VS Code, CLI)
///   ↓ JSON-RPC over stdio (JSONL)
/// cmd/app-server
///   ↓ gateway transform pipeline
///   ↓ HTTP
/// Any backend (OpenAI, Anthropic, Gemini, Ollama...)
/// ```

///|
let default_config : String = "gateway-config.json"

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
// State management
// =============================================================================

///|
struct AppServerState {
  mut thread_counter : Int
  mut turn_counter : Int
  mut item_counter : Int
  threads : Map[String, ThreadState]
  gateway : @gw.Gateway
}

///|
struct ThreadState {
  id : String
  mut model : String
  cwd : String
  approval_policy : String
  mut active_turn_id : String?
  history : Array[Json]
}

///|
fn AppServerState::new(gateway : @gw.Gateway) -> AppServerState {
  {
    thread_counter: 0,
    turn_counter: 0,
    item_counter: 0,
    threads: {},
    gateway,
  }
}

///|
fn AppServerState::next_thread_id(self : AppServerState) -> String {
  self.thread_counter = self.thread_counter + 1
  "thr_" + self.thread_counter.to_string()
}

///|
fn AppServerState::next_turn_id(self : AppServerState) -> String {
  self.turn_counter = self.turn_counter + 1
  "turn_" + self.turn_counter.to_string()
}

///|
fn AppServerState::next_item_id(self : AppServerState) -> String {
  self.item_counter = self.item_counter + 1
  "item_" + self.item_counter.to_string()
}

// =============================================================================
// JSON-RPC response helpers (delegate to protocol layer)
// =============================================================================

///|
fn send_response(id : Int?, result : Json) -> String {
  @codex.codex_rpc_response(id, result)
}

///|
fn send_error(id : Int?, code : Int, message : String) -> String {
  @codex.codex_rpc_error(id, code, message)
}

///|
fn send_notification(rpc_method : String, params : Json) -> String {
  @codex.codex_rpc_notification(rpc_method, params)
}

// =============================================================================
// Request handlers
// =============================================================================

///|
fn handle_initialize(
  _state : AppServerState,
  id : Int?,
  _params : Json?,
) -> Array[String] {
  let result : Json = {
    "protocolVersion": "2025-01-01",
    "capabilities": {
      "experimental": {},
      "modelList": { "supported": true },
    },
    "serverInfo": { "name": "llm_interop-app-server", "version": "0.1.0" },
    "userAgent": "llm_interop-app-server/0.1.0",
  }
  [send_response(id, result)]
}

///|
fn handle_thread_start(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let p = match params {
    Some(p) => p
    None => return [send_error(id, -32602, "Missing params")]
  }
  let thread_params = match @codex.CodexThreadStartParams::from_json(p) {
    Some(tp) => tp
    None => return [send_error(id, -32602, "Invalid thread/start params")]
  }
  let thread_id = state.next_thread_id()
  let thread_state : ThreadState = {
    id: thread_id,
    model: thread_params.model,
    cwd: thread_params.cwd,
    approval_policy: thread_params.approval_policy,
    active_turn_id: None,
    history: [],
  }
  state.threads[thread_id] = thread_state
  let result : Json = {
    "thread": { "id": thread_id },
    "model": thread_params.model,
    "approvalPolicy": thread_params.approval_policy,
  }
  let response = send_response(id, result)
  // Also send thread/started notification
  let notification = send_notification(
    "thread/started",
    { "thread": { "id": thread_id } },
  )
  [response, notification]
}


///|
async fn handle_model_list(
  state : AppServerState,
  id : Int?,
  _params : Json?,
  emit : async (String) -> Unit,
) -> Unit {
  let models : Array[Json] = []
  let seen_ids : Map[String, Bool] = {}
  for _, provider in state.gateway.config.providers {
    // Skip Codex app-server providers (we ARE the app-server)
    if provider.api == @gw.ModelApi::CodexAppServer {
      continue
    }
    // 1. Config models — always included as baseline
    for m in provider.models {
      if not(seen_ids.contains(m.id)) {
        models.push(@gw.model_config_to_codex_model_json(m, provider.id))
        seen_ids[m.id] = true
      }
    }
    // 2. Endpoint models — additionally fetched when modelsFromEndpoint: true
    if provider.models_from_endpoint {
      let endpoint_models = fetch_provider_models(provider)
      for rm in endpoint_models {
        match rm {
          { "id": String(model_id), .. } =>
            if not(seen_ids.contains(model_id)) {
              models.push(
                @gw.enrich_remote_model_json(
                  model_id, provider.id, provider.models,
                ),
              )
              seen_ids[model_id] = true
            }
          _ => ()
        }
      }
    }
  }
  let result : Json = { "data": Json::array(models) }
  emit(send_response(id, result))
}


///|
fn handle_turn_interrupt(
  _state : AppServerState,
  id : Int?,
  _params : Json?,
) -> Array[String] {
  [send_response(id, {})]
}

// =============================================================================
// Thread management extensions
// =============================================================================

///|
fn handle_thread_resume(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let p = match params {
    Some(p) => p
    None => return [send_error(id, -32602, "Missing params")]
  }
  let resume_params = match @codex.CodexThreadResumeParams::from_json(p) {
    Some(rp) => rp
    None => return [send_error(id, -32602, "Invalid thread/resume params")]
  }
  let thread = match state.threads.get(resume_params.thread_id) {
    Some(t) => t
    None =>
      return [
        send_error(
          id,
          -32602,
          "Unknown thread: " + resume_params.thread_id,
        ),
      ]
  }
  let result : Json = {
    "thread": { "id": thread.id },
    "model": thread.model,
    "approvalPolicy": thread.approval_policy,
  }
  let response = send_response(id, result)
  let notification = send_notification(
    "thread/started",
    { "thread": { "id": thread.id } },
  )
  [response, notification]
}

///|
fn handle_thread_fork(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let p = match params {
    Some(p) => p
    None => return [send_error(id, -32602, "Missing params")]
  }
  let fork_params = match @codex.CodexThreadForkParams::from_json(p) {
    Some(fp) => fp
    None => return [send_error(id, -32602, "Invalid thread/fork params")]
  }
  let source = match state.threads.get(fork_params.thread_id) {
    Some(t) => t
    None =>
      return [
        send_error(
          id,
          -32602,
          "Unknown thread: " + fork_params.thread_id,
        ),
      ]
  }
  let new_id = state.next_thread_id()
  let new_thread : ThreadState = {
    id: new_id,
    model: source.model,
    cwd: source.cwd,
    approval_policy: source.approval_policy,
    active_turn_id: None,
    history: source.history.copy(),
  }
  state.threads[new_id] = new_thread
  let result : Json = { "thread": { "id": new_id } }
  let response = send_response(id, result)
  let notification = send_notification(
    "thread/started",
    { "thread": { "id": new_id } },
  )
  [response, notification]
}

///|
fn handle_thread_list(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let list_params = match params {
    Some(p) =>
      match @codex.CodexThreadListParams::from_json(p) {
        Some(lp) => lp
        None => { cursor: None, limit: 25, sort_key: "created_at", archived: false, cwd: None }
      }
    None => { cursor: None, limit: 25, sort_key: "created_at", archived: false, cwd: None }
  }
  let threads : Array[Json] = []
  let mut skip = 0
  // Simple cursor: use thread counter as cursor value
  match list_params.cursor {
    Some(c) =>
      skip = @strconv.parse_int(c) catch { _ => 0 }
    None => ()
  }
  let mut count = 0
  for _, thread in state.threads {
    // Apply cwd filter
    match list_params.cwd {
      Some(filter_cwd) => if thread.cwd != filter_cwd { continue }
      None => ()
    }
    if count < skip {
      count = count + 1
      continue
    }
    if threads.length() >= list_params.limit {
      break
    }
    let obj : Map[String, Json] = {}
    obj["id"] = Json::string(thread.id)
    obj["preview"] = Json::string("")
    obj["ephemeral"] = false.to_json()
    obj["modelProvider"] = Json::string("proxy")
    threads.push(Json::object(obj))
    count = count + 1
  }
  let next_cursor : Json = if threads.length() >= list_params.limit {
    Json::string(count.to_string())
  } else {
    Json::null()
  }
  let result : Json = {
    "data": Json::array(threads),
    "nextCursor": next_cursor,
  }
  [send_response(id, result)]
}

// =============================================================================
// Turn steer
// =============================================================================

///|
fn handle_turn_steer(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let p = match params {
    Some(p) => p
    None => return [send_error(id, -32602, "Missing params")]
  }
  let steer_params = match @codex.CodexTurnSteerParams::from_json(p) {
    Some(sp) => sp
    None => return [send_error(id, -32602, "Invalid turn/steer params")]
  }
  let thread = match state.threads.get(steer_params.thread_id) {
    Some(t) => t
    None =>
      return [
        send_error(
          id,
          -32602,
          "Unknown thread: " + steer_params.thread_id,
        ),
      ]
  }
  // Verify active turn matches
  match thread.active_turn_id {
    Some(active_id) =>
      if active_id != steer_params.expected_turn_id {
        return [
          send_error(
            id,
            -32602,
            "Turn ID mismatch: expected " +
            steer_params.expected_turn_id +
            " but active is " +
            active_id,
          ),
        ]
      }
    None =>
      return [send_error(id, -32602, "No active turn on thread")]
  }
  // Append input to history (will be reflected in next turn)
  let user_text = StringBuilder::new()
  for item in steer_params.input {
    if user_text.to_string().length() > 0 {
      user_text.write_string("\n")
    }
    user_text.write_string(item.text)
  }
  let steer_msg : Json = { "role": "user", "content": user_text.to_string() }
  thread.history.push(steer_msg)
  let turn_id = match thread.active_turn_id {
    Some(tid) => tid
    None => ""
  }
  [send_response(id, { "turnId": turn_id })]
}

// =============================================================================
// Protocol stubs (Approval, review, skills, MCP)
// =============================================================================

///|
fn handle_thread_archive(
  _state : AppServerState,
  id : Int?,
  _params : Json?,
) -> Array[String] {
  [send_response(id, {})]
}

///|
fn handle_review_start(
  state : AppServerState,
  id : Int?,
  params : Json?,
) -> Array[String] {
  let thread_id = match params {
    Some({ "threadId": String(tid), .. }) => tid
    _ => ""
  }
  let turn_id = state.next_turn_id()
  let result : Json = {
    "turn": { "id": turn_id, "status": "completed" },
    "reviewThreadId": thread_id,
  }
  [send_response(id, result)]
}

///|
fn handle_skills_list(
  _state : AppServerState,
  id : Int?,
  _params : Json?,
) -> Array[String] {
  [send_response(id, { "data": Json::array([]) })]
}

///|
fn handle_mcp_not_supported(id : Int?) -> Array[String] {
  [send_error(id, -32601, "Not supported in proxy mode")]
}

///|
fn handle_approval_resolve(id : Int?) -> Array[String] {
  [send_response(id, { "resolved": true })]
}

// =============================================================================
// HTTP client
// =============================================================================

///|
/// Streaming HTTP POST — reads SSE chunks and calls on_delta for each content delta.
/// Returns (accumulated_content, input_tokens, output_tokens, total_tokens).
async fn http_post_streaming(
  req : @gw.UpstreamRequest,
  on_delta : async (String) -> Unit,
) -> (String, Int, Int, Int) raise {
  let client = @http.Client::new(req.origin) catch {
    e => raise @gw.GatewayError::NetworkError("Failed to connect: " + e.to_string())
  }
  let _response = client.post(req.path, req.body, extra_headers=req.headers) catch {
    e => {
      client.close()
      raise @gw.GatewayError::NetworkError("Request failed: " + e.to_string())
    }
  }
  // Read SSE stream line by line
  let content = StringBuilder::new()
  let mut remaining = ""
  let mut input_tokens = 0
  let mut output_tokens = 0
  let mut total_tokens = 0
  while @io.Reader::read_until(client, "\n") is Some(line) {
    let to_parse = remaining + line + "\n"
    let parsed = @sse.parse_openai_sse_chunk(to_parse)
    remaining = parsed.remaining
    for event in parsed.events {
      // Extract content delta
      match event.data {
        {
          "choices": [
            { "delta": { "content": String(text), .. }, .. },
            ..
          ],
          ..
        } =>
          if text != "" {
            content.write_string(text)
            on_delta(text)
          }
        _ => ()
      }
      // Check for usage in final chunk
      match @codex.sse_chunk_extract_usage(event.data) {
        Some((it, ot, tt)) => {
          input_tokens = it
          output_tokens = ot
          total_tokens = tt
        }
        None => ()
      }
    }
  }
  client.close()
  (content.to_string(), input_tokens, output_tokens, total_tokens)
}

// =============================================================================
// Model fetching per provider type
// =============================================================================

///|
/// Fetch models from a provider's endpoint.
/// Returns [] if the provider has no model listing capability or fetch fails.
async fn fetch_provider_models(provider : @gw.ProviderConfig) -> Array[Json] {
  match provider.api {
    // Claude MCP has no model listing endpoint
    @gw.ModelApi::ClaudeMcpServe => []
    // Codex: query model/list via stdio subprocess
    @gw.ModelApi::CodexAppServer => fetch_codex_model_list(provider)
    // HTTP providers: query /v1/models (or equivalent)
    _ => {
      let base_url = expand_env(provider.base_url)
      let api_key = expand_env(provider.api_key)
      if base_url == "" || api_key == "" {
        return []
      }
      let upstream = @gw.prepare_models_request(provider, base_url, api_key)
      let (status, response_text) = http_get(upstream)
      if status != 200 {
        return []
      }
      @gw.parse_models_response(response_text, provider.id)
    }
  }
}

// =============================================================================
// Codex JSON-RPC stdio transport for model/list
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

// =============================================================================

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

// Dispatch (emit-based for streaming support)
// =============================================================================

///|
async fn emit_all(
  emit : async (String) -> Unit,
  messages : Array[String],
) -> Unit {
  for msg in messages {
    emit(msg)
  }
}

///|
async fn dispatch(
  state : AppServerState,
  text : String,
  emit : async (String) -> Unit,
) -> Unit {
  let json = @json.parse(text) catch {
    _ => {
      emit(send_error(None, -32700, "Parse error"))
      return
    }
  }
  let req = match @jsonrpc.RpcRequest::from_json(json) {
    Some(r) => r
    None => {
      emit(send_error(None, -32600, "Invalid Request"))
      return
    }
  }
  match req.rpc_method {
    "initialize" =>
      emit_all(emit, handle_initialize(state, req.id, req.params))
    "initialized" => () // Notification, no response
    // Thread management
    "thread/start" =>
      emit_all(emit, handle_thread_start(state, req.id, req.params))
    "thread/resume" =>
      emit_all(emit, handle_thread_resume(state, req.id, req.params))
    "thread/fork" =>
      emit_all(emit, handle_thread_fork(state, req.id, req.params))
    "thread/list" =>
      emit_all(emit, handle_thread_list(state, req.id, req.params))
    "thread/archive" | "thread/unarchive" =>
      emit_all(emit, handle_thread_archive(state, req.id, req.params))
    // Turn management
    "turn/start" =>
      handle_turn_start_streaming(state, req.id, req.params, emit)
    "turn/interrupt" =>
      emit_all(emit, handle_turn_interrupt(state, req.id, req.params))
    "turn/steer" =>
      emit_all(emit, handle_turn_steer(state, req.id, req.params))
    // Model listing (async — fetches from all providers)
    "model/list" =>
      handle_model_list(state, req.id, req.params, emit)
    // Review
    "review/start" =>
      emit_all(emit, handle_review_start(state, req.id, req.params))
    // Skills
    "skills/list" =>
      emit_all(emit, handle_skills_list(state, req.id, req.params))
    // MCP
    "mcpServer/oauth/login" =>
      emit_all(emit, handle_mcp_not_supported(req.id))
    "config/mcpServer/reload" => emit(send_response(req.id, {}))
    "mcpServerStatus/list" =>
      emit(send_response(req.id, { "data": Json::array([]) }))
    // Approval resolution
    "item/commandExecution/resolveApproval"
    | "item/fileChange/resolveApproval" =>
      emit_all(emit, handle_approval_resolve(req.id))
    _ =>
      emit(
        send_error(req.id, -32601, "Method not found: " + req.rpc_method),
      )
  }
}

///|
/// Streaming version of handle_turn_start — emits events as they arrive
async fn handle_turn_start_streaming(
  state : AppServerState,
  id : Int?,
  params : Json?,
  emit : async (String) -> Unit,
) -> Unit {
  let p = match params {
    Some(p) => p
    None => {
      emit(send_error(id, -32602, "Missing params"))
      return
    }
  }
  let turn_params = match @codex.CodexTurnStartParams::from_json(p) {
    Some(tp) => tp
    None => {
      emit(send_error(id, -32602, "Invalid turn/start params"))
      return
    }
  }
  let thread = match state.threads.get(turn_params.thread_id) {
    Some(t) => t
    None => {
      emit(
        send_error(
          id,
          -32602,
          "Unknown thread: " + turn_params.thread_id,
        ),
      )
      return
    }
  }
  let turn_id = state.next_turn_id()
  let item_id = state.next_item_id()
  thread.active_turn_id = Some(turn_id)
  // Update model if provided
  if turn_params.model != "codex" && turn_params.model != "" {
    thread.model = turn_params.model
  }
  // Extract text from input items
  let user_text = StringBuilder::new()
  for item in turn_params.input {
    if user_text.to_string().length() > 0 {
      user_text.write_string("\n")
    }
    user_text.write_string(item.text)
  }
  let prompt = user_text.to_string()
  // Add user message to history
  let user_msg : Json = { "role": "user", "content": prompt }
  thread.history.push(user_msg)
  // Send turn/start RPC response
  let turn_response : Json = {
    "turn": { "id": turn_id, "status": "inProgress" },
  }
  emit(send_response(id, turn_response))
  // Build OpenAI Chat Completions request with stream: true
  let messages_json = Json::array(thread.history.copy())
  let req_obj : Map[String, Json] = {}
  req_obj["model"] = Json::string(thread.model)
  req_obj["messages"] = messages_json
  req_obj["stream"] = true.to_json()
  req_obj["stream_options"] = { "include_usage": true }
  match turn_params.effort {
    Some(e) => req_obj["reasoning_effort"] = Json::string(e)
    None => ()
  }
  let request_body = Json::object(req_obj).stringify()
  // Select backend
  let model = thread.model
  let provider = match state.gateway.select_backend(model) {
    Some(p) => p
    None => {
      emit(@codex.make_turn_started_event(turn_id))
      emit(
        @codex.make_turn_failed_event(
          turn_id,
          "No backend available for model: " + model,
        ),
      )
      thread.active_turn_id = None
      return
    }
  }
  // Prepare upstream request
  let base_url = expand_env(provider.base_url)
  let api_key = expand_env(provider.api_key)
  let upstream = @gw.prepare_upstream(
    provider,
    request_body,
    @gw.GatewaySurface::OpenAI,
    model,
    base_url,
    api_key,
  )
  // Emit turn/started and item/started before streaming begins
  emit(@codex.make_turn_started_event(turn_id))
  emit(@codex.make_item_started_event(item_id))
  // Stream response
  let (content, input_tokens, output_tokens, total_tokens) = try {
    http_post_streaming(upstream, async fn(delta_text) {
      emit(@codex.make_agent_message_delta_event(item_id, delta_text))
    })
  } catch {
    e => {
      emit(
        @codex.make_turn_failed_event(turn_id, e.to_string()),
      )
      thread.active_turn_id = None
      return
    }
  }
  // Emit completion events
  emit(@codex.make_item_completed_event(item_id, content))
  emit(
    @codex.make_token_usage_event(input_tokens, output_tokens, total_tokens),
  )
  emit(@codex.make_turn_completed_event(turn_id, item_id, content))
  // Add assistant message to history
  if content != "" {
    let assistant_msg : Json = {
      "role": "assistant",
      "content": content,
    }
    thread.history.push(assistant_msg)
  }
  thread.active_turn_id = None
}

// =============================================================================
// WebSocket transport
// =============================================================================

///|
async fn run_ws_server(
  state : AppServerState,
  host : String,
  port : Int,
) -> Unit {
  let addr_str = host + ":" + port.to_string()
  let addr = @socket.Addr::parse(addr_str) catch {
    _ => {
      @stdio.stderr.write("Failed to parse address: \{addr_str}\n")
      return
    }
  }
  let server = @http.Server::new(addr, reuse_addr=true) catch {
    e => {
      @stdio.stderr.write("Failed to start WebSocket server: \{e}\n")
      return
    }
  }
  @stdio.stderr.write(
    "Codex app-server listening on ws://\{host}:\{port}\n",
  )
  server.run_forever((request, _, conn) => {
    let ws = @websocket.from_http_server(request, conn) catch {
      _ => return
    }
    defer ws.close()
    try {
      for ;; {
        let msg = ws.recv()
        match msg.kind {
          Text => {
            let text = @io.Reader::read_all(msg).text()
            dispatch(state, text, async fn(s) { ws.send_text(s) })
          }
          _ => () // Ignore binary frames
        }
      }
    } catch {
      @websocket.ConnectionClosed(_, _) => ()
      _ => ()
    }
  })
}

// =============================================================================
// CLI + Main
// =============================================================================

///|
struct CliOptions {
  config_path : String
  ws_port : Int?
  help : Bool
}

///|
fn parse_args(args : Array[String]) -> CliOptions {
  let mut config_path = default_config
  let mut ws_port : Int? = None
  let mut help = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      help = true
    } else if arg == "--config" || arg == "-c" {
      i = i + 1
      if i < args.length() {
        config_path = args[i]
      }
    } else if arg == "--ws-port" {
      i = i + 1
      if i < args.length() {
        ws_port = Some(@strconv.parse_int(args[i]) catch { _ => 8765 })
      }
    }
    i = i + 1
  }
  { config_path, ws_port, help }
}

///|
fn print_help() -> Unit {
  println(
    "Codex app-server frontend - LLM backend proxy\n\nUsage: app-server [options]\n\nOptions:\n  -c, --config <path>    Path to gateway config file (default: \{default_config})\n      --ws-port <port>   Start WebSocket server instead of stdio\n  -h, --help             Show this help message\n\nDefault: reads JSON-RPC from stdin, writes to stdout.\nWith --ws-port: listens on ws://0.0.0.0:<port>.",
  )
}

///|
async fn run() -> Unit {
  let args = @sys.get_cli_args()
  let opts = parse_args(args)
  if opts.help {
    print_help()
    return
  }
  let config = load_config(opts.config_path) catch {
    e => {
      @stdio.stderr.write("Error: \{e}\n")
      @sys.exit(1)
      return
    }
  }
  let gateway = @gw.Gateway::new(config, @gw.GatewaySurface::OpenAI)
  let state = AppServerState::new(gateway)
  // Choose transport mode
  match opts.ws_port {
    Some(port) =>
      // WebSocket server mode
      run_ws_server(state, "0.0.0.0", port)
    None =>
      // stdio mode (default)
      while @stdio.stdin.read_until("\n") is Some(line) {
        let trimmed = line.trim_end(chars="\n\r").to_string()
        if trimmed == "" {
          continue
        }
        dispatch(state, trimmed, async fn(s) { @stdio.stdout.write(s + "\n") })
      }
  }
}

///|
async fn main {
  run()
}
