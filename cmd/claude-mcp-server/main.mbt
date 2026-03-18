///|
/// MCP server frontend — emulates `claude mcp serve`
///
/// Speaks MCP protocol over stdio (JSONL) to MCP clients.
/// Each model in gateway-config.json is exposed as an MCP tool.
/// Tools/call requests are proxied to LLM backends via the gateway.
///
/// ```
/// MCP client (Claude Code, Cursor, etc.)
///   ↓ MCP over stdio (JSONL)
/// cmd/claude-mcp-server
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
// State
// =============================================================================

///|
struct McpServerState {
  gateway : @gw.Gateway
  tools : Array[@mcp.McpToolDefinition]
}

///|
fn McpServerState::new(
  gateway : @gw.Gateway,
  tools : Array[@mcp.McpToolDefinition],
) -> McpServerState {
  { gateway, tools }
}

// =============================================================================
// Tool construction from config
// =============================================================================

///|
/// Build tools from config-defined models.
/// Config `models` are always included as the baseline for all providers.
/// MCP protocol has no model discovery — endpoint fetch is not available here.
fn build_tools_from_config(
  config : @gw.GatewayConfig,
) -> Array[@mcp.McpToolDefinition] {
  let tools : Array[@mcp.McpToolDefinition] = []
  for provider_id, provider in config.providers {
    for model in provider.models {
      tools.push(
        @claude_mcp.model_to_mcp_tool(model.id, model.name, provider_id),
      )
    }
  }
  tools
}

// =============================================================================
// HTTP client (non-streaming)
// =============================================================================

///|
async fn http_post(
  req : @gw.UpstreamRequest,
) -> (Int, String) {
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
      return (502, "{\"error\":{\"message\":\"Failed to read: \{e}\"}}")
    }
  }
  let text = response_body.text() catch { _ => "" }
  client.close()
  (response.code, text)
}

// =============================================================================
// Handlers
// =============================================================================

///|
fn handle_initialize(_state : McpServerState, id : Int) -> String {
  @claude_mcp.build_initialize_result(id)
}

///|
fn handle_tools_list(state : McpServerState, id : Int) -> String {
  @claude_mcp.build_tools_list_result(id, state.tools)
}

///|
async fn handle_tools_call(
  state : McpServerState,
  id : Int,
  params : Json?,
) -> String {
  // 1. Parse tools/call params
  let call_params = match @claude_mcp.parse_tools_call_params(params) {
    Some(p) => p
    None =>
      return @jsonrpc.build_error_response(
        Some(id), -32602, "Invalid tools/call params",
      )
  }
  let tool_name = call_params.name
  let args = @claude_mcp.extract_prompt_args(call_params.arguments)
  // 2. Select backend
  let backend = match state.gateway.select_backend(tool_name) {
    Some(b) => b
    None =>
      return @claude_mcp.build_tools_call_result(
        id, "No backend found for model: " + tool_name, true,
      )
  }
  // 3. Build chat request (OpenAI format — gateway transforms to target dialect)
  let request_body = @claude_mcp.build_chat_request(
    tool_name, args.prompt, args.system, args.max_tokens,
  )
  // 4. Prepare upstream
  let base_url = expand_env(backend.provider.base_url)
  let api_key = expand_env(backend.provider.api_key)
  let upstream = @gw.prepare_upstream(
    backend.provider,
    request_body,
    @gw.GatewaySurface::OpenAI,
    tool_name,
    base_url,
    api_key,
  )
  // 5. HTTP POST (non-streaming)
  let (status, response_body) = http_post(upstream)
  if status != 200 {
    return @claude_mcp.build_tools_call_result(
      id,
      "Upstream error (HTTP " + status.to_string() + "): " + response_body,
      true,
    )
  }
  // 6. Transform response to OpenAI format if needed
  let from_surface = backend.provider.api.to_dialect()
  let normalized = @gw.transform_response(
    response_body, from_surface, @gw.GatewaySurface::OpenAI,
  )
  // 7. Extract content
  let content = @claude_mcp.extract_assistant_content(normalized)
  // 8. Build MCP result
  @claude_mcp.build_tools_call_result(id, content, false)
}

// =============================================================================
// Dispatch
// =============================================================================

///|
async fn dispatch(
  state : McpServerState,
  text : String,
  emit : async (String) -> Unit,
) -> Unit {
  let json = @json.parse(text) catch {
    _ => {
      emit(@jsonrpc.build_error_response(None, -32700, "Parse error"))
      return
    }
  }
  let req = match @jsonrpc.RpcRequest::from_json(json) {
    Some(r) => r
    None => {
      emit(@jsonrpc.build_error_response(None, -32600, "Invalid Request"))
      return
    }
  }
  match req.rpc_method {
    "initialize" =>
      match req.id {
        Some(id) => emit(handle_initialize(state, id))
        None => ()
      }
    "notifications/initialized" => () // no-op notification
    "tools/list" =>
      match req.id {
        Some(id) => emit(handle_tools_list(state, id))
        None => ()
      }
    "tools/call" =>
      match req.id {
        Some(id) => emit(handle_tools_call(state, id, req.params))
        None => ()
      }
    "ping" =>
      match req.id {
        Some(id) => emit(@claude_mcp.build_ping_result(id))
        None => ()
      }
    _ =>
      emit(
        @jsonrpc.build_error_response(
          req.id, -32601, "Method not found: " + req.rpc_method,
        ),
      )
  }
}

// =============================================================================
// CLI + Main
// =============================================================================

///|
struct CliOptions {
  config_path : String
  help : Bool
}

///|
fn parse_args(args : Array[String]) -> CliOptions {
  let mut config_path = default_config
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
    }
    i = i + 1
  }
  { config_path, help }
}

///|
fn print_help() -> Unit {
  println(
    "MCP server frontend - LLM backend proxy (emulates `claude mcp serve`)\n\nUsage: claude-mcp-server [options]\n\nOptions:\n  -c, --config <path>    Path to gateway config file (default: \{default_config})\n  -h, --help             Show this help message\n\nReads MCP JSON-RPC from stdin, writes to stdout.\nEach model in config is exposed as an MCP tool.",
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
  let tools = build_tools_from_config(config)
  let gateway = @gw.Gateway::new(config, @gw.GatewaySurface::OpenAI)
  let state = McpServerState::new(gateway, tools)
  @stdio.stderr.write(
    "claude-mcp-server: \{tools.length()} tools available\n",
  )
  // stdio JSONL loop
  while @stdio.stdin.read_until("\n") is Some(line) {
    let trimmed = line.trim_end(chars="\n\r").to_string()
    if trimmed == "" {
      continue
    }
    dispatch(state, trimmed, async fn(s) { @stdio.stdout.write(s + "\n") })
  }
}

///|
async fn main {
  run()
}
