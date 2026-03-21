///|
/// LLM API Client — gateway-based, all ModelApi providers via HttpTransport

///|
pub suberror ClientError {
  HttpError(String)
  ParseError(String)
  ApiError(code~ : Int, message~ : String)
} derive(Show)

// =============================================================================
// chat_gateway — canonical entry point for all providers
// =============================================================================

///|
/// Send a chat request using gateway-based routing.
/// Supports all ModelApi providers via HttpTransport injection.
///
/// Pipeline:
///   1. Build body in OpenAI Chat Completions format (lingua franca)
///   2. prepare_upstream(): transform_request(OpenAI → provider dialect), URL, headers, aliases
///   3. HTTP POST via injected HttpTransport
///   4. transform_response(provider dialect → OpenAI): includes tool_use/functionCall conversion
///   5. parse_chat_response(): unified OpenAI-format parser
///
/// Exception: OpenAIResponses API has its own body/response format.
/// Gateway does not have Chat Completions ↔ Responses API transform.
pub async fn chat_gateway(
  provider : @gateway.ProviderConfig,
  transport : &HttpTransport,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  max_tokens? : Int? = None,
  temperature? : Double? = None,
) -> @types.ModelResponse raise ClientError {
  let api = provider.api
  let uses_responses_api = api == @gateway.OpenAIResponses
  // 1. Build body
  let body = if uses_responses_api {
    @openai.build_responses_api_body(model, messages, tools).stringify()
  } else {
    @openai.build_chat_body(
      model, messages, tools, max_tokens~, temperature~,
    ).stringify()
  }
  // 2. prepare_upstream: transform_request + URL + headers + model aliases
  let base_url = if provider.base_url.is_empty() {
    api.default_base_url()
  } else {
    provider.base_url
  }
  let upstream = @gateway.prepare_upstream(
    provider,
    body,
    @gateway.GatewaySurface::OpenAI,
    model,
    base_url,
    provider.api_key,
  )
  // 3. HTTP POST
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
  // 4. Parse response
  if uses_responses_api {
    let json = @json.parse(resp.body) catch {
      err =>
        raise ClientError::ParseError("JSON parse error: " + err.to_string())
    }
    @openai.parse_responses_api_response(json)
  } else {
    // transform_response: provider dialect → OpenAI (including tool_use/functionCall → tool_calls)
    let openai_body = @gateway.transform_response(
      resp.body,
      api.to_dialect(),
      @gateway.GatewaySurface::OpenAI,
    )
    let json = @json.parse(openai_body) catch {
      err =>
        raise ClientError::ParseError("JSON parse error: " + err.to_string())
    }
    @openai.parse_chat_response(json)
  }
}
