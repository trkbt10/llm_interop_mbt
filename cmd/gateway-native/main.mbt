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
      buf.write_char(Char::from_int(s[i].to_int()))
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
    @gw.RouteResult::CompletionWithModel(dialect~, model~, body~) =>
      proxy_to_backend(gateway, @utils.inject_json_field(body, "model", model), dialect, model)
    @gw.RouteResult::NotFound(path~, dialect~) =>
      @gw.HttpResponse::error(
        404,
        "Not found: " + path + " (dialect: " + dialect + ")",
      )
  }
}

// =============================================================================
// HTTP transport - the only async/native-dependent code
// =============================================================================

///|
/// Select backend and proxy request
async fn proxy_to_backend(
  gateway : @gw.Gateway,
  body : String,
  target_dialect : @chat.Dialect,
  model : String,
) -> @gw.HttpResponse {
  let backend = match gateway.select_backend(model) {
    Some(b) => b
    None =>
      return @gw.HttpResponse::error(
        503,
        "No backend available for model: " + model,
      )
  }
  let base_url = expand_env(backend.provider.base_url)
  let api_key = expand_env(backend.provider.api_key)
  let upstream = @gw.prepare_upstream(
    backend.provider, body, target_dialect, model, base_url, api_key,
  )
  let (status, response_text) = http_post(upstream)
  let final_body = @chat.transform_response(
    response_text,
    backend.provider.api.to_dialect(),
    target_dialect,
  )
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  { status, headers, body: final_body }
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
    if models.length() == 0 {
      errors.push(
        "No models returned from \{provider.id}, response: \{response_text}",
      )
      continue
    }
    for m in models {
      all_models.push(m)
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
