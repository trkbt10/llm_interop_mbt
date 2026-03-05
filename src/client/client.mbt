///|
/// LLM API Client using mizchi/x/http

///|
pub suberror ClientError {
  HttpError(String)
  ParseError(String)
  ApiError(code~ : Int, message~ : String)
} derive(Show)

///|
/// API Provider type
pub(all) enum Provider {
  Anthropic
  OpenAI
  OpenAICompatible(base_url~ : String)
}

///|
/// Client configuration
pub(all) struct ClientConfig {
  provider : Provider
  api_key : String
  model : String
  max_tokens : Int
  temperature : Double?
}

///|
pub fn ClientConfig::new(
  provider : Provider,
  api_key : String,
  model : String,
  max_tokens~ : Int = 4096,
  temperature~ : Double? = None
) -> ClientConfig {
  { provider, api_key, model, max_tokens, temperature }
}

///|
fn get_endpoint(provider : Provider) -> String {
  match provider {
    Anthropic => "https://api.anthropic.com/v1/messages"
    OpenAI => "https://api.openai.com/v1/chat/completions"
    OpenAICompatible(base_url~) => base_url + "/v1/chat/completions"
  }
}

///|
fn get_headers(config : ClientConfig) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  match config.provider {
    Anthropic => {
      headers["x-api-key"] = config.api_key
      headers["anthropic-version"] = "2023-06-01"
    }
    OpenAI | OpenAICompatible(_) => {
      headers["Authorization"] = "Bearer " + config.api_key
    }
  }
  headers
}

///|
fn build_request_body(
  config : ClientConfig,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition]
) -> String {
  let body = match config.provider {
    Anthropic =>
      @protocol.build_anthropic_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
    OpenAI | OpenAICompatible(_) =>
      @protocol.build_openai_chat_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
  }
  body.stringify()
}

///|
fn parse_response(config : ClientConfig, json : Json) -> @types.ModelResponse {
  match config.provider {
    Anthropic => @protocol.parse_anthropic_response(json)
    OpenAI | OpenAICompatible(_) => @protocol.parse_openai_chat_response(json)
  }
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  @encoding.decode_lossy(bytes[:])
}

///|
/// Send a chat request (non-streaming)
pub async fn chat(
  config : ClientConfig,
  messages : Array[@types.ModelMessage],
  tools~ : Array[@types.ToolDefinition] = []
) -> @types.ModelResponse raise ClientError {
  let url = get_endpoint(config.provider)
  let headers = get_headers(config)
  let body = build_request_body(config, messages, tools)
  let body_data : &@io.Data = body
  let (response, data) = @http.post(url, body_data, headers~) catch {
    @http.HttpError::NetworkError(msg) => raise ClientError::HttpError(msg)
    @http.HttpError::InvalidUrl(msg) => raise ClientError::HttpError("Invalid URL: " + msg)
    @http.HttpError::TimeoutError => raise ClientError::HttpError("Request timeout")
    @http.HttpError::NotSupported => raise ClientError::HttpError("HTTP not supported on this platform")
  }
  let response_str = data.text() catch {
    err => raise ClientError::ParseError("Failed to read response: " + err.to_string())
  }
  if response.code >= 400 {
    raise ClientError::ApiError(code=response.code, message=response_str)
  }
  let json = @json.parse(response_str) catch {
    err => raise ClientError::ParseError("JSON parse error: " + err.to_string())
  }
  parse_response(config, json)
}

///|
/// Stream event from SSE
pub(all) struct StreamEvent {
  event : String
  data : Json
}

///|
/// Send a chat request with streaming
pub async fn chat_stream(
  config : ClientConfig,
  messages : Array[@types.ModelMessage],
  tools~ : Array[@types.ToolDefinition] = [],
  on_event~ : (StreamEvent) -> Unit = fn(_) {  }
) -> @types.ModelResponse raise ClientError {
  let url = get_endpoint(config.provider)
  let headers = get_headers(config)
  // Add stream parameter to body
  let body_json = match config.provider {
    Anthropic => {
      let base = @protocol.build_anthropic_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
      set_json_field(base, "stream", Json::boolean(true))
    }
    OpenAI | OpenAICompatible(_) => {
      let base = @protocol.build_openai_chat_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
      set_json_field(base, "stream", Json::boolean(true))
    }
  }
  let body = body_json.stringify()
  let body_data : &@io.Data = body
  let (response, stream) = @http.post_stream(url, body_data, headers~) catch {
    @http.HttpError::NetworkError(msg) => raise ClientError::HttpError(msg)
    @http.HttpError::InvalidUrl(msg) => raise ClientError::HttpError("Invalid URL: " + msg)
    @http.HttpError::TimeoutError => raise ClientError::HttpError("Request timeout")
    @http.HttpError::NotSupported => raise ClientError::HttpError("HTTP not supported on this platform")
  }
  if response.code >= 400 {
    let body_bytes = stream.read_all() catch {
      _ => b""
    }
    let body_str = bytes_to_string(body_bytes)
    raise ClientError::ApiError(code=response.code, message=body_str)
  }
  // Create accumulator based on provider
  let buffer = StringBuilder::new()
  let all_events : Array[@sse.SseEvent] = []
  // Read stream chunks
  while true {
    let chunk = stream.read_some() catch {
      _ => break
    }
    match chunk {
      None => break
      Some(bytes) => {
        let text = bytes_to_string(bytes)
        buffer.write_string(text)
        // Try to parse complete events from buffer
        let content = buffer.to_string()
        let result = parse_sse_events(content, config.provider)
        for e in result.events {
          on_event({ event: e.event, data: e.data })
          all_events.push(e)
        }
        buffer.reset()
        buffer.write_string(result.remaining)
      }
    }
  }
  // Process remaining buffer
  let remaining = buffer.to_string()
  if remaining.length() > 0 {
    let result = parse_sse_events(remaining + "\n", config.provider)
    for e in result.events {
      on_event({ event: e.event, data: e.data })
      all_events.push(e)
    }
  }
  // Accumulate all events
  match config.provider {
    Anthropic => {
      let acc = @sse.AnthropicMessagesAccumulator::new()
      for e in all_events {
        acc.feed(e)
      }
      acc.finish()
    }
    OpenAI | OpenAICompatible(_) => {
      let acc = @sse.ChatCompletionsAccumulator::new()
      for e in all_events {
        acc.feed(e)
      }
      acc.finish()
    }
  }
}

///|
fn set_json_field(json : Json, key : String, value : Json) -> Json {
  match json {
    Object(map) => {
      map[key] = value
      Json::object(map)
    }
    _ => json
  }
}

///|
priv struct ParsedEvents {
  events : Array[@sse.SseEvent]
  remaining : String
}

///|
fn parse_sse_events(content : String, provider : Provider) -> ParsedEvents {
  let events : Array[@sse.SseEvent] = []
  let lines = split_lines(content)
  let remaining = StringBuilder::new()
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let trimmed = line.trim().to_string()
    // Check if this might be an incomplete line (last line without proper ending)
    if i == lines.length() - 1 && trimmed.length() > 0 && not(content.has_suffix("\n")) {
      // Keep as remaining for next chunk
      remaining.write_string(line)
      break
    }
    if trimmed.length() == 0 || trimmed == "[DONE]" {
      i = i + 1
      continue
    }
    // Parse based on provider format
    match provider {
      Anthropic => {
        // Anthropic uses "event: type\ndata: json" format
        if trimmed.has_prefix("event:") {
          let event_type = safe_substring(trimmed, 6)
          i = i + 1
          if i < lines.length() {
            let data_line = lines[i].trim().to_string()
            if data_line.has_prefix("data:") {
              let data_str = safe_substring(data_line, 5)
              let data = @json.parse(data_str) catch { _ => Json::null() }
              events.push({ event: event_type, data })
            }
          }
        } else if trimmed.has_prefix("data:") {
          let data_str = safe_substring(trimmed, 5)
          let data = @json.parse(data_str) catch { _ => Json::null() }
          events.push({ event: "", data })
        }
      }
      OpenAI | OpenAICompatible(_) => {
        // OpenAI uses "data: json" format
        if trimmed.has_prefix("data:") {
          let data_str = safe_substring(trimmed, 5)
          if data_str != "[DONE]" {
            let data = @json.parse(data_str) catch { _ => Json::null() }
            events.push({ event: "", data })
          }
        }
      }
    }
    i = i + 1
  }
  { events, remaining: remaining.to_string() }
}

///|
fn safe_substring(s : String, start : Int) -> String {
  if start >= s.length() {
    return ""
  }
  let buf = StringBuilder::new()
  let mut idx = 0
  for c in s {
    if idx >= start {
      buf.write_char(c)
    }
    idx = idx + 1
  }
  buf.to_string().trim().to_string()
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for c in s {
    if c == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else if c == '\r' {
      continue
    } else {
      buf.write_char(c)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}
