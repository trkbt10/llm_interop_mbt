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
  max_tokens? : Int = 4096,
  temperature? : Double? = None,
) -> ClientConfig {
  { provider, api_key, model, max_tokens, temperature }
}

///|
fn get_endpoint(provider : Provider) -> String {
  match provider {
    Anthropic => @anthropic.anthropic_default_base_url() + "/messages"
    OpenAI => @openai.chat_completions_default_base_url() + "/chat/completions"
    OpenAICompatible(base_url~) => base_url + "/v1/chat/completions"
  }
}

///|
fn get_headers(config : ClientConfig) -> Map[String, String] {
  match config.provider {
    Anthropic => @anthropic.anthropic_auth_headers(config.api_key)
    OpenAI | OpenAICompatible(_) =>
      @openai.chat_completions_auth_headers(config.api_key)
  }
}

///|
fn build_request_body(
  config : ClientConfig,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
) -> String {
  let body = match config.provider {
    Anthropic =>
      @anthropic.build_anthropic_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
    OpenAI | OpenAICompatible(_) =>
      @openai.build_openai_chat_body(
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
    Anthropic => @anthropic.parse_anthropic_response(json)
    OpenAI | OpenAICompatible(_) => @openai.parse_openai_chat_response(json)
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
  tools? : Array[@types.ToolDefinition] = [],
) -> @types.ModelResponse raise ClientError {
  let url = get_endpoint(config.provider)
  let headers = get_headers(config)
  let body = build_request_body(config, messages, tools)
  let body_data : &@io.Data = body
  let (response, data) = @http.post(url, body_data, headers~) catch {
    @http.HttpError::NetworkError(msg) => raise ClientError::HttpError(msg)
    @http.HttpError::InvalidUrl(msg) =>
      raise ClientError::HttpError("Invalid URL: " + msg)
    @http.HttpError::TimeoutError =>
      raise ClientError::HttpError("Request timeout")
    @http.HttpError::NotSupported =>
      raise ClientError::HttpError("HTTP not supported on this platform")
  }
  let response_str = data.text() catch {
    err =>
      raise ClientError::ParseError(
        "Failed to read response: " + err.to_string(),
      )
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
/// Select the appropriate SSE chunk parser for a provider
fn get_chunk_parser(provider : Provider) -> (String) -> @sse.ParsedChunk {
  match provider {
    Anthropic => @sse.parse_anthropic_sse_chunk
    OpenAI | OpenAICompatible(_) => @sse.parse_openai_sse_chunk
  }
}

///|
/// Send a chat request with streaming
pub async fn chat_stream(
  config : ClientConfig,
  messages : Array[@types.ModelMessage],
  tools? : Array[@types.ToolDefinition] = [],
  on_event? : (StreamEvent) -> Unit = fn(_) {  },
) -> @types.ModelResponse raise ClientError {
  let url = get_endpoint(config.provider)
  let headers = get_headers(config)
  let body_json = match config.provider {
    Anthropic => {
      let base = @anthropic.build_anthropic_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
      @utils.set_json_field(base, "stream", Json::boolean(true))
    }
    OpenAI | OpenAICompatible(_) => {
      let base = @openai.build_openai_chat_body(
        config.model,
        messages,
        tools,
        max_tokens=Some(config.max_tokens),
        temperature=config.temperature,
      )
      @utils.set_json_field(base, "stream", Json::boolean(true))
    }
  }
  let body = body_json.stringify()
  let body_data : &@io.Data = body
  let (response, stream) = @http.post_stream(url, body_data, headers~) catch {
    @http.HttpError::NetworkError(msg) => raise ClientError::HttpError(msg)
    @http.HttpError::InvalidUrl(msg) =>
      raise ClientError::HttpError("Invalid URL: " + msg)
    @http.HttpError::TimeoutError =>
      raise ClientError::HttpError("Request timeout")
    @http.HttpError::NotSupported =>
      raise ClientError::HttpError("HTTP not supported on this platform")
  }
  if response.code >= 400 {
    let body_bytes = stream.read_all() catch { _ => b"" }
    let body_str = bytes_to_string(body_bytes)
    raise ClientError::ApiError(code=response.code, message=body_str)
  }
  let parse_chunk = get_chunk_parser(config.provider)
  let buffer = StringBuilder::new()
  let all_events : Array[@sse.SseEvent] = []
  while true {
    let chunk = stream.read_some() catch { _ => break }
    match chunk {
      None => break
      Some(bytes) => {
        let text = bytes_to_string(bytes)
        buffer.write_string(text)
        let result = parse_chunk(buffer.to_string())
        for e in result.events {
          on_event({ event: e.event, data: e.data })
          all_events.push(e)
        }
        buffer.reset()
        buffer.write_string(result.remaining)
      }
    }
  }
  let remaining = buffer.to_string()
  if remaining.length() > 0 {
    let result = parse_chunk(remaining + "\n")
    for e in result.events {
      on_event({ event: e.event, data: e.data })
      all_events.push(e)
    }
  }
  match config.provider {
    Anthropic => {
      let acc = @anthropic.AnthropicMessagesAccumulator::new()
      for e in all_events {
        acc.feed(e)
      }
      acc.finish()
    }
    OpenAI | OpenAICompatible(_) => {
      let acc = @openai.ChatCompletionsAccumulator::new()
      for e in all_events {
        acc.feed(e)
      }
      acc.finish()
    }
  }
}
