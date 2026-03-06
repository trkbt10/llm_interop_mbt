///|
/// LLM Gateway CLI - Native HTTP Server

///|
/// Defaults
let default_port : Int = 18080

///|
let default_host : String = "0.0.0.0"

///|
let default_config : String = "gateway-config.json"

///|
/// CLI options
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
  println("Backends: \{gateway.config.backends.length()}")
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
    // Handle CORS preflight
    if meth == "OPTIONS" {
      let headers : Map[String, String] = {}
      headers["Access-Control-Allow-Origin"] = "*"
      headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
      headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      conn.send_response(204, "No Content", extra_headers=headers)
      conn.end_response()
      return
    }
    let response = gateway.route(meth, req.path, body_text)
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
async fn main {
  let args = @sys.get_cli_args()
  let opts = parse_args(args)
  if opts.help {
    print_help()
    return
  }
  // Load config
  let base_config = load_config(opts.config_path) catch {
    e => {
      println("Error: \{e}")
      @sys.exit(1)
      return
    }
  }
  // Override with CLI args
  let config : @gw.GatewayConfig = {
    ..base_config,
    server: { host: opts.host, port: opts.port },
  }
  let gateway = @gw.Gateway::new(config, opts.dialect)
  run_server(gateway, opts.host, opts.port)
}
