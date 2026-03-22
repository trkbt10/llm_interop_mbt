///|
/// Responses API pipeline entry points (sync and streaming).
///
/// All cross-dialect translation uses Responses API as the intermediate format.
/// Backend routing:
///   OpenAIResponses    → pass through (native)
///   OpenAICompletions  → Harmony pipeline
///   AnthropicMessages  → direct Responses API → Anthropic conversion
///   GoogleGenerativeAI → direct Responses API → Gemini conversion

// =============================================================================
// Sync
// =============================================================================

///|
/// Send a chat request using Responses API as the intermediate format.
///
/// Pipeline:
///   1. Build body in Responses API format (intermediate representation)
///   2. gateway.prepare_responses_api_upstream(): direct conversion to backend format
///   3. HTTP POST via injected HttpTransport
///   4. Parse response: native Responses API direct, others via translator pipeline

///|
/// Inject optional max_tokens and temperature into a Responses API body.
fn inject_optional_params(
  body : Json,
  max_tokens : Int?,
  temperature : Double?,
) -> Unit {
  match max_tokens {
    Some(n) =>
      match body {
        Object(obj) => obj["max_output_tokens"] = Json::number(n.to_double())
        _ => ()
      }
    None => ()
  }
  match temperature {
    Some(t) =>
      match body {
        Object(obj) => obj["temperature"] = Json::number(t)
        _ => ()
      }
    None => ()
  }
}

///|
pub async fn chat_gateway_responses(
  provider : @gateway.ProviderConfig,
  transport : &HttpTransport,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  max_tokens? : Int? = None,
  temperature? : Double? = None,
) -> @types.ModelResponse raise ClientError {
  let responses_body = @openai.build_responses_api_body(model, messages, tools)
  inject_optional_params(responses_body, max_tokens, temperature)
  let base_url = if provider.base_url.is_empty() {
    provider.api.default_base_url()
  } else {
    provider.base_url
  }
  let upstream = @gateway.prepare_responses_api_upstream(
    provider,
    responses_body,
    model,
    base_url,
    provider.api_key,
  )
  let url = upstream.origin + upstream.path
  let req : TransportRequest = {
    url,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(upstream.body),
  }
  let resp = transport.request(req) catch {
    TransportError::NetworkError(msg) =>
      raise ClientError::HttpError("Transport error: " + msg)
    TransportError::TimeoutError =>
      raise ClientError::HttpError("Transport timeout")
  }
  if resp.status == 429 {
    return @types.ModelResponse::RateLimited(retry_after=60)
  }
  if resp.status < 200 || resp.status >= 300 {
    raise ClientError::ApiError(code=resp.status, message=resp.body)
  }
  @gateway.parse_responses_api_result(provider.api, resp.body, model~)
}

// =============================================================================
// Streaming
// =============================================================================

///|
/// Send a streaming chat request using Responses API as the intermediate format.
/// SSE events from the backend are translated to Responses API events and
/// delivered via the on_event callback.
///
/// Pipeline:
///   1. Build Responses API body
///   2. Convert to backend format with stream=true
///   3. HTTP streaming POST via StreamingHttpTransport
///   4. SSE parse → backend translator → Responses API events → on_event callback
///   5. Accumulate into final ModelResponse
pub async fn chat_gateway_responses_stream(
  provider : @gateway.ProviderConfig,
  transport : &StreamingHttpTransport,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  on_event~ : ((String, Json)) -> Unit,
  max_tokens? : Int? = None,
  temperature? : Double? = None,
) -> @types.ModelResponse raise ClientError {
  let responses_body = @openai.build_responses_api_body(model, messages, tools)
  inject_optional_params(responses_body, max_tokens, temperature)
  let base_url = if provider.base_url.is_empty() {
    provider.api.default_base_url()
  } else {
    provider.base_url
  }
  let upstream = @gateway.prepare_responses_api_upstream(
    provider,
    responses_body,
    model,
    base_url,
    provider.api_key,
    stream=true,
  )
  let url = upstream.origin + upstream.path
  let req : TransportRequest = {
    url,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(upstream.body),
  }
  let streaming_resp = transport.request_stream(req) catch {
    TransportError::NetworkError(msg) =>
      raise ClientError::HttpError("Transport error: " + msg)
    TransportError::TimeoutError =>
      raise ClientError::HttpError("Transport timeout")
  }
  if streaming_resp.status == 429 {
    return @types.ModelResponse::RateLimited(retry_after=60)
  }
  if streaming_resp.status < 200 || streaming_resp.status >= 300 {
    let error_body = read_all_from_stream(streaming_resp.reader) catch {
      _ => ""
    }
    raise ClientError::ApiError(code=streaming_resp.status, message=error_body)
  }
  let api = provider.api
  let response_id = @gateway.fallback_response_id(model)
  let translator = @gateway.create_responses_api_translator(
    api,
    response_id~,
    model~,
  )
  let acc = @openai.ResponsesApiAccumulator::new()
  let mut sse_buffer = ""
  while true {
    let chunk = streaming_resp.reader.read() catch {
      TransportError::NetworkError(msg) =>
        raise ClientError::HttpError("Stream read error: " + msg)
      TransportError::TimeoutError =>
        raise ClientError::HttpError("Stream read timeout")
    }
    match chunk {
      None => break
      Some(bytes) => {
        let text = bytes_to_string_lossy(bytes)
        let parsed = @sse.parse_sse_chunk(sse_buffer + text)
        sse_buffer = parsed.remaining
        for event in parsed.events {
          let responses_events = translator.translate(event)
          for re in responses_events {
            let (event_type, event_data) = re
            on_event((event_type, event_data))
            acc.feed({ event: event_type, data: event_data })
          }
        }
      }
    }
  }
  acc.finish()
}
