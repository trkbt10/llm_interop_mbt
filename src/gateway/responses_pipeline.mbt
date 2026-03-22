///|
/// Responses API Pipeline — request/response conversion using Responses API
/// as the intermediate format (lingua franca).
///
/// Request conversion (Responses API → backend):
///   OpenAI Responses API → pass through (native)
///   Chat Completions     → @harmony.responses_request_to_chat_completions
///   Anthropic Messages   → @anthropic.responses_request_to_anthropic (direct)
///   Gemini               → @gemini.responses_request_to_gemini (direct)
///
/// Streaming SSE translation (backend SSE → Responses API events):
///   Chat Completions SSE → HarmonyToResponsesTranslator
///   Anthropic SSE        → AnthropicToResponsesTranslator
///   Gemini SSE           → GeminiToResponsesTranslator
///   Responses API SSE    → pass through

// =============================================================================
// Request conversion
// =============================================================================

///|
/// Convert a Responses API body to the backend's format and build an
/// UpstreamRequest. Selects the correct direct conversion based on provider.api.
pub fn prepare_responses_api_upstream(
  provider : ProviderConfig,
  responses_body : Json,
  model : String,
  base_url : String,
  api_key : String,
  stream? : Bool = false,
) -> UpstreamRequest {
  let api = provider.api
  let converted_body = convert_responses_request(api, responses_body, stream)
  let (origin, base_path) = @utils.parse_url(base_url)
  let path = api.completion_path(base_path, model, api_key)
  let headers = api.auth_headers(api_key)
  for key, value in provider.headers {
    headers[key] = value
  }
  // Apply model alias
  let backend_model = match provider.model_aliases.get(model) {
    Some(mapped) => mapped
    None => model
  }
  let final_body = if backend_model != model {
    replace_model_in_body(converted_body, backend_model)
  } else {
    converted_body
  }
  { origin, path, headers, body: final_body }
}

///|
/// Convert Responses API body to the backend's request format.
fn convert_responses_request(
  api : ModelApi,
  responses_body : Json,
  stream : Bool,
) -> String {
  match api {
    OpenAIResponses =>
      // Native Responses API: pass through, inject stream flag
      if stream {
        @utils.set_json_field(responses_body, "stream", Json::boolean(true)).stringify()
      } else {
        responses_body.stringify()
      }
    OpenAICompletions
    | Ollama
    | GithubCopilot
    | BedrockConverseStream
    | OpenRouter
    | CodexAppServer
    | ClaudeMcpServe =>
      // Chat Completions compatible: Harmony pipeline
      @harmony.responses_request_to_chat_completions(responses_body, stream~).stringify()
    AnthropicMessages =>
      // Anthropic: direct conversion
      if stream {
        @anthropic.responses_request_to_anthropic_stream(responses_body).stringify()
      } else {
        @anthropic.responses_request_to_anthropic(responses_body).stringify()
      }
    GoogleGenerativeAI =>
      // Gemini: direct conversion
      // Note: Gemini streaming uses a different endpoint path, not a body flag.
      // The stream flag is handled via endpoint selection in completion_path.
      @gemini.responses_request_to_gemini(responses_body).stringify()
  }
}

// =============================================================================
// Response ID extraction (delegates to interop/id SoT)
// =============================================================================

///|
/// Extract response ID from a backend response body.
/// Delegates to @interop_util.extract_or_generate_response_id (SoT).
pub fn extract_response_id(response_body : String, model : String) -> String {
  @interop_util.extract_or_generate_response_id(
    response_body,
    @interop_util.ResponseIdProvider::OpenAIResponsesApi,
    model,
  )
}

///|
/// Generate a fallback response ID when the backend doesn't provide one.
/// Delegates to @interop_util.generate_response_id_for_model (SoT).
pub fn fallback_response_id(model : String) -> String {
  @interop_util.generate_response_id_for_model(
    @interop_util.ResponseIdProvider::OpenAIResponsesApi,
    model,
  )
}

// =============================================================================
// Non-streaming response parsing
// =============================================================================

///|
/// Parse a non-streaming backend response into a ModelResponse.
/// Uses the translator pipeline: backend response → synthetic SSE events
/// → Responses API translator → ResponsesApiAccumulator → ModelResponse.
/// Responses API is the intermediate format at every step.
pub fn parse_responses_api_result(
  api : ModelApi,
  response_body : String,
  model~ : String,
) -> @types.ModelResponse {
  if api == OpenAIResponses {
    // Native Responses API: parse directly
    let json = @json.parse(response_body) catch {
      _ => return @types.ModelResponse::ModelError("JSON parse error")
    }
    return @openai.parse_responses_api_response(json)
  }
  // Other backends: synthetic events → translator → Responses API accumulator
  let response_id = extract_response_id(response_body, model)
  let synthetic_events = to_synthetic_sse_events(api, response_body)
  let translator = create_responses_api_translator(api, response_id~, model~)
  let acc = @openai.ResponsesApiAccumulator::new()
  for event in synthetic_events {
    let responses_events = translator.translate(event)
    for re in responses_events {
      let (event_type, event_data) = re
      acc.feed({ event: event_type, data: event_data })
    }
  }
  acc.finish()
}

// =============================================================================
// Streaming SSE translation
// =============================================================================

///|
/// Stateful SSE translator. Translates backend SSE events to Responses API events.
/// Created per-request via create_responses_api_translator().
pub(all) enum ResponsesApiTranslator {
  /// Chat Completions SSE → Responses API events
  Harmony(@harmony.HarmonyToResponsesTranslator)
  /// Anthropic SSE → Responses API events
  Anthropic(@anthropic.AnthropicToResponsesTranslator)
  /// Gemini SSE → Responses API events
  Gemini(@gemini.GeminiToResponsesTranslator)
  /// Native Responses API SSE → pass through
  PassThrough
}

///|
/// Create a translator for the given backend API type.
pub fn create_responses_api_translator(
  api : ModelApi,
  response_id~ : String,
  model? : String = "",
) -> ResponsesApiTranslator {
  match api {
    OpenAIResponses => PassThrough
    OpenAICompletions
    | Ollama
    | GithubCopilot
    | BedrockConverseStream
    | OpenRouter
    | CodexAppServer
    | ClaudeMcpServe =>
      Harmony(@harmony.HarmonyToResponsesTranslator::new(response_id~, model~))
    AnthropicMessages =>
      Anthropic(@anthropic.AnthropicToResponsesTranslator::new(response_id~))
    GoogleGenerativeAI =>
      Gemini(@gemini.GeminiToResponsesTranslator::new(response_id~, model~))
  }
}

///|
/// Translate a single backend SSE event to Responses API events.
pub fn ResponsesApiTranslator::translate(
  self : ResponsesApiTranslator,
  event : @sse.SseEvent,
) -> Array[(String, Json)] {
  match self {
    Harmony(t) => t.translate(event)
    Anthropic(t) => t.translate(event)
    Gemini(t) => t.translate(event)
    PassThrough => [(event.event, event.data)]
  }
}

///|
/// Convert a non-streaming backend response to synthetic SSE events for
/// translator pipeline unification. Each dialect owns its own conversion.
///
/// Note: OpenAIResponses returns empty — native Responses API responses should
/// be parsed directly via parse_responses_api_response, not via synthetic events.
pub fn to_synthetic_sse_events(
  api : ModelApi,
  response_body : String,
) -> Array[@sse.SseEvent] {
  let json = @json.parse(response_body) catch { _ => return [] }
  match api {
    OpenAIResponses =>
      // Native Responses API: not applicable for synthetic events.
      // Callers should use parse_responses_api_response directly.
      []
    OpenAICompletions
    | Ollama
    | GithubCopilot
    | BedrockConverseStream
    | OpenRouter
    | CodexAppServer
    | ClaudeMcpServe => @harmony.chat_completion_to_synthetic_events(json)
    AnthropicMessages => @anthropic.non_streaming_to_synthetic_events(json)
    GoogleGenerativeAI => @gemini.non_streaming_to_synthetic_events(json)
  }
}
