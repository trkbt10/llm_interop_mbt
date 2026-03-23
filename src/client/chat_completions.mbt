///|
/// Chat Completions pass-through entry point.
///
/// Same dialect (Chat Completions → Chat Completions backend): no translation.
/// Cross-dialect or Responses API backend: delegates to chat_gateway_responses
/// which uses Responses API as the intermediate format.

///|
fn build_chat_gateway_request(
  provider : @gateway.ProviderConfig,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  max_tokens : Int?,
  temperature : Double?,
  response_format : @types.ResponseFormat?,
) -> TransportRequest {
  let api = provider.api
  let body = @openai.build_chat_body(
    model,
    messages,
    tools,
    max_tokens~,
    temperature~,
    response_format~,
  ).stringify()
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
  let url = upstream.origin + upstream.path
  {
    url,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(upstream.body),
  }
}

///|
fn parse_chat_gateway_transport_response(
  resp : TransportResponse,
) -> @types.ModelResponse raise ClientError {
  if resp.status == 429 {
    return @types.ModelResponse::RateLimited(retry_after=60)
  }
  if resp.status < 200 || resp.status >= 300 {
    raise ClientError::ApiError(code=resp.status, message=resp.body)
  }
  let json = @json.parse(resp.body) catch {
    err => raise ClientError::ParseError("JSON parse error: " + err.to_string())
  }
  @openai.parse_chat_response(json)
}

///|
pub async fn chat_gateway(
  provider : @gateway.ProviderConfig,
  transport : &HttpTransport,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  model : String,
  max_tokens? : Int? = None,
  temperature? : Double? = None,
  response_format? : @types.ResponseFormat? = None,
) -> @types.ModelResponse raise ClientError {
  let api = provider.api
  let target = api.to_dialect()
  // Cross-dialect or native Responses API → Responses API intermediate
  if target != @gateway.GatewaySurface::OpenAI ||
    api == @gateway.OpenAIResponses {
    return chat_gateway_responses(
      provider,
      transport,
      messages,
      tools,
      model,
      max_tokens~,
      temperature~,
      response_format~,
    )
  }
  // Same dialect: Chat Completions pass through (no translation)
  let req = build_chat_gateway_request(
    provider, messages, tools, model, max_tokens, temperature, response_format,
  )
  let resp = transport.request(req) catch {
    TransportError::NetworkError(msg) =>
      raise ClientError::HttpError("Transport error: " + msg)
    TransportError::TimeoutError =>
      raise ClientError::HttpError("Transport timeout")
  }
  parse_chat_gateway_transport_response(resp)
}
