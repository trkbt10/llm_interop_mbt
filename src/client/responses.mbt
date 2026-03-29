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
/// Inject optional generation parameters into a Responses API body.
/// Per Responses API spec:
///   https://platform.openai.com/docs/api-reference/responses/create
///
/// Supported parameters:
///   max_output_tokens — maximum output tokens
///   temperature — sampling temperature (0.0-2.0)
///   top_p — nucleus sampling (0.0-1.0)
///   reasoning.effort — for reasoning models ("low" | "medium" | "high")
///
/// When all are None, nothing is injected (model defaults apply).
fn inject_optional_params(
  body : Json,
  max_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  reasoning_effort : String?,
) -> Unit {
  match body {
    Object(obj) => {
      match max_tokens {
        Some(n) => obj["max_output_tokens"] = Json::number(n.to_double())
        None => ()
      }
      match temperature {
        Some(t) => obj["temperature"] = Json::number(t)
        None => ()
      }
      match top_p {
        Some(p) => obj["top_p"] = Json::number(p)
        None => ()
      }
      match reasoning_effort {
        Some(r) => obj["reasoning"] = Json::object(
          { "effort": Json::string(r) },
        )
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Apply response_format to the final upstream request body using the target
/// provider's native request surface. This avoids OpenAI-specific schema
/// normalization leaking into Anthropic/Gemini requests.
fn apply_response_format_to_transport_body(
  api : @gateway.ModelApi,
  body : String,
  response_format : @types.ResponseFormat?,
) -> String {
  match response_format {
    None => body
    Some(format) => {
      let json = @json.parse(body) catch { _ => return body }
      match json {
        Object(obj) => {
          let params : @types.GenerationParams = {
            ..@types.GenerationParams::empty(),
            response_format: Some(format),
          }
          match api {
            @gateway.OpenAIResponses => params.apply_to_responses(obj)
            @gateway.AnthropicMessages =>
              params.apply_to_anthropic(obj, @types.TransformContext::default())
            @gateway.GoogleGenerativeAI =>
              params.apply_to_gemini(obj, @types.TransformContext::default())
            _ => params.apply_to_openai(obj, @types.TransformContext::default())
          }
          Json::object(obj).stringify()
        }
        _ => body
      }
    }
  }
}

///|
fn build_responses_transport_request(
  provider : @gateway.ProviderConfig,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  max_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  reasoning_effort : String?,
  response_format : @types.ResponseFormat?,
  stream : Bool,
) -> TransportRequest {
  let responses_body = @openai.build_responses_api_body(model, messages, tools)
  inject_optional_params(
    responses_body, max_tokens, temperature, top_p, reasoning_effort,
  )
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
    stream~,
  )
  let url = upstream.origin + upstream.path
  let final_body = apply_response_format_to_transport_body(
    provider.api,
    upstream.body,
    response_format,
  )
  {
    url,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(final_body),
  }
}

///|
fn parse_responses_transport_response(
  api : @gateway.ModelApi,
  model : String,
  resp : TransportResponse,
) -> @types.ModelResponse raise ClientError {
  if resp.status == 429 {
    return @types.ModelResponse::Failure(
      failure=@types.ModelFailure::rate_limited(
        retry_after=60,
        body=Some(resp.body),
      ),
    )
  }
  if resp.status < 200 || resp.status >= 300 {
    raise ClientError::ApiError(code=resp.status, message=resp.body)
  }
  @gateway.parse_responses_api_result(api, resp.body, model~)
}

///|
fn process_responses_stream_chunk(
  translator : @gateway.ResponsesApiTranslator,
  acc : @openai.ResponsesApiAccumulator,
  validator : StructuredStreamValidator,
  sse_buffer : String,
  bytes : Bytes,
  on_event : ((String, Json)) -> Unit,
) -> String raise ClientError {
  let text = bytes_to_string_lossy(bytes)
  let parsed = @sse.parse_sse_chunk(sse_buffer + text)
  for event in parsed.events {
    let responses_events = translator.translate(event)
    for re in responses_events {
      let (event_type, event_data) = re
      validator.feed(event_type, event_data)
      on_event((event_type, event_data))
      acc.feed({ event: event_type, data: event_data })
    }
  }
  parsed.remaining
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
  top_p? : Double? = None,
  reasoning_effort? : String? = None,
  response_format? : @types.ResponseFormat? = None,
) -> @types.ModelResponse raise ClientError {
  let req = build_responses_transport_request(
    provider, messages, tools, model, max_tokens, temperature,
    top_p, reasoning_effort, response_format, false,
  )
  let resp = transport.request(req) catch {
    TransportError::NetworkError(msg) =>
      raise ClientError::HttpError("Transport error: " + msg)
    TransportError::TimeoutError =>
      raise ClientError::HttpError("Transport timeout")
  }
  parse_responses_transport_response(provider.api, model, resp)
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
  top_p? : Double? = None,
  reasoning_effort? : String? = None,
  response_format? : @types.ResponseFormat? = None,
) -> @types.ModelResponse raise ClientError {
  let req = build_responses_transport_request(
    provider, messages, tools, model, max_tokens, temperature,
    top_p, reasoning_effort, response_format, true,
  )
  let streaming_resp = transport.request_stream(req) catch {
    TransportError::NetworkError(msg) =>
      raise ClientError::HttpError("Transport error: " + msg)
    TransportError::TimeoutError =>
      raise ClientError::HttpError("Transport timeout")
  }
  if streaming_resp.status == 429 {
    return @types.ModelResponse::Failure(
      failure=@types.ModelFailure::rate_limited(retry_after=60),
    )
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
  let validator = StructuredStreamValidator::new(response_format)
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
      Some(bytes) =>
        sse_buffer = process_responses_stream_chunk(
          translator, acc, validator, sse_buffer, bytes, on_event,
        )
    }
  }
  validator.finish()
  acc.finish()
}
