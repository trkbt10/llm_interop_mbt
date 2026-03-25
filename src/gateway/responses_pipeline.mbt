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
  let path = match (api, stream) {
    (GoogleGenerativeAI, true) =>
      @gemini.stream_completion_path(base_path, model, api_key)
    _ => api.completion_path(base_path, model, api_key)
  }
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
/// Rationale: non-Responses backends frequently omit a stable response id on
/// non-streaming success payloads, but our translated Responses/OpenAI flows
/// still need one so `response.created`, `response.in_progress`, and the final
/// `response.completed` envelope all point at the same logical response. Without
/// a generated id, downstream accumulators cannot correlate lifecycle events
/// with the terminal payload in a backend-agnostic way.
/// Reference:
/// - docs/upstream/openai-responses-create.md documents the Responses envelope
///   shape with `response.id`.
/// - The id-generation policy itself stays centralized in
///   @interop_util.generate_response_id_for_model(...), which is the SoT for
///   synthetic/gateway-generated response ids.
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
/// Prefers native/direct backend parsers when available. Falls back to the
/// translator pipeline only for dialects that only expose chat/event shapes:
/// backend response → synthetic SSE events → Responses API translator
/// → ResponsesApiAccumulator → ModelResponse.
pub fn parse_responses_api_result(
  api : ModelApi,
  response_body : String,
  model~ : String,
) -> @types.ModelResponse {
  match direct_model_response_from_backend(api, response_body) {
    Some(response) => return response
    None => ()
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

///|
fn direct_model_response_from_backend(
  api : ModelApi,
  response_body : String,
) -> @types.ModelResponse? {
  match api {
    OpenAIResponses => {
      let json = @json.parse(response_body) catch {
        _ =>
          return Some(
            @types.ModelResponse::Failure(
              failure=@types.ModelFailure::parse_error(
                message="JSON parse error",
                body=Some(response_body),
              ),
            ),
          )
      }
      Some(@openai.parse_responses_api_response(json))
    }
    OpenAICompletions
    | Ollama
    | GithubCopilot
    | BedrockConverseStream
    | OpenRouter => Some(parse_openai_chat_response_or_failure(response_body))
    AnthropicMessages =>
      Some(parse_anthropic_response_or_failure(response_body))
    GoogleGenerativeAI => Some(parse_gemini_response_or_failure(response_body))
    CodexAppServer =>
      Some(
        parse_openai_chat_response_or_failure(
          @codex.response_to_chat(response_body),
        ),
      )
    ClaudeMcpServe => Some(@claude_mcp.parse_response(response_body))
  }
}

///|
fn parse_openai_chat_response_or_failure(
  response_body : String,
) -> @types.ModelResponse {
  let json = @json.parse(response_body) catch {
    _ =>
      return @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="JSON parse error",
          body=Some(response_body),
        ),
      )
  }
  @openai.parse_chat_response(json)
}

///|
fn parse_anthropic_response_or_failure(
  response_body : String,
) -> @types.ModelResponse {
  let json = @json.parse(response_body) catch {
    _ =>
      return @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="JSON parse error",
          body=Some(response_body),
        ),
      )
  }
  @anthropic.parse_response(json)
}

///|
fn parse_gemini_response_or_failure(
  response_body : String,
) -> @types.ModelResponse {
  let json = @json.parse(response_body) catch {
    _ =>
      return @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="JSON parse error",
          body=Some(response_body),
        ),
      )
  }
  @gemini.parse_response(json)
}

///|
/// Transform a non-streaming backend response into canonical OpenAI Responses
/// JSON. This is the preserve-first response-side counterpart to
/// prepare_responses_api_upstream(...).
pub fn transform_response_to_responses_json(
  api : ModelApi,
  response_body : String,
  model~ : String,
) -> Json {
  match direct_responses_json_from_backend(api, response_body, model) {
    Some(response_json) => return response_json
    None => ()
  }
  let response_id = extract_response_id(response_body, model)
  let parsed = parse_responses_api_result(api, response_body, model~)
  @openai_responses_contract.model_response_to_responses_json(
    parsed,
    response_id~,
    model~,
  )
}

///|
fn direct_responses_json_from_backend(
  api : ModelApi,
  response_body : String,
  model : String,
) -> Json? {
  match api {
    OpenAIResponses =>
      Some(
        @json.parse(response_body) catch {
          _ => responses_parse_error_json(response_body, model)
        },
      )
    AnthropicMessages => {
      let json = @json.parse(response_body) catch {
        _ => return Some(responses_parse_error_json(response_body, model))
      }
      Some(
        @anthropic.response_to_responses(
          json,
          response_id=extract_response_id(response_body, model),
        ),
      )
    }
    GoogleGenerativeAI => {
      let json = @json.parse(response_body) catch {
        _ => return Some(responses_parse_error_json(response_body, model))
      }
      Some(
        @gemini.response_to_responses(
          json,
          response_id=extract_response_id(response_body, model),
          model~,
        ),
      )
    }
    ClaudeMcpServe =>
      Some(
        @claude_mcp.response_to_responses(
          response_body,
          response_id=extract_response_id(response_body, model),
          model~,
        ),
      )
    _ => None
  }
}

///|
fn responses_parse_error_json(response_body : String, model : String) -> Json {
  @openai_responses_contract.model_response_to_responses_json(
    @types.ModelResponse::Failure(
      failure=@types.ModelFailure::parse_error(
        message="JSON parse error",
        body=Some(response_body),
      ),
    ),
    response_id=fallback_response_id(model),
    model~,
  )
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
  /// Codex JSONL events → Responses API events
  Codex(@codex.CodexToResponsesTranslator)
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
    | ClaudeMcpServe =>
      Harmony(@harmony.HarmonyToResponsesTranslator::new(response_id~, model~))
    CodexAppServer =>
      Codex(@codex.CodexToResponsesTranslator::new(response_id~, model~))
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
    Codex(t) => t.translate(event)
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
  // Rationale: this helper is best-effort and is only used by legacy synthetic
  // event paths and test helpers. The main sync response path parses the body
  // first via direct_model_response_from_backend(...) or
  // direct_responses_json_from_backend(...), so returning [] here does not
  // silently turn malformed upstream JSON into a successful response. We keep
  // the helper non-throwing because its job is "convert an already trusted body
  // into synthetic events", not "decide whether the upstream call succeeded".
  // Reference:
  // - parse_responses_api_result(...) above is the authoritative sync parser.
  // - transform_response_to_responses_json(...) above is the authoritative
  //   preserve-first response serializer.
  // - responses_pipeline_wbtest.mbt covers this helper separately as a
  //   synthetic-event utility rather than the source of truth for error
  //   handling.
  let json = @json.parse(response_body) catch { _ => return [] }
  match api {
    OpenAIResponses => responses_json_to_synthetic_events(json)
    OpenAICompletions
    | Ollama
    | GithubCopilot
    | BedrockConverseStream
    | OpenRouter
    | ClaudeMcpServe => @harmony.chat_completion_to_synthetic_events(json)
    CodexAppServer => @codex.non_streaming_to_synthetic_events(json)
    AnthropicMessages => @anthropic.non_streaming_to_synthetic_events(json)
    GoogleGenerativeAI => @gemini.non_streaming_to_synthetic_events(json)
  }
}

///|
fn responses_json_to_synthetic_events(
  response_json : Json,
) -> Array[@sse.SseEvent] {
  let response = @openai.parse_responses_api_response(response_json)
  match response.as_failure() {
    Some(_) => []
    None => {
      let response_id = match response_json {
        { "id": String(id), .. } => id
        // Rationale: synthetic Responses events still need a stable id even when
        // the source fixture/body omitted one, because every synthetic lifecycle
        // event emitted below must refer to the same response id. This is not a
        // semantic fallback for model content; it is envelope completion for a
        // partial source payload.
        // Reference:
        // - docs/upstream/openai-responses-create.md response envelope.
        // - The centralized SoT in fallback_response_id(...).
        _ => fallback_response_id("")
      }
      let model = match response_json {
        { "model": String(model), .. } => model
        _ => ""
      }
      let output = @openai_responses_contract.model_response_to_responses_output(
        response,
      )
      let events : Array[@sse.SseEvent] = [
        {
          event: "response.created",
          data: {
            "type": "response.created",
            "response": { "id": response_id },
          },
        },
        {
          event: "response.in_progress",
          data: {
            "type": "response.in_progress",
            "response": { "id": response_id, "status": "in_progress" },
          },
        },
      ]
      for output_index in 0..<output.length() {
        let item = output[output_index]
        emit_responses_output_item_events(events, item, output_index)
      }
      let completed_response : Map[String, Json] = {
        "id": Json::string(response_id),
        "status": Json::string("completed"),
        "output": Json::array(output),
      }
      if model.length() > 0 {
        completed_response["model"] = Json::string(model)
      }
      events.push({
        event: "response.completed",
        data: {
          "type": "response.completed",
          "response": Json::object(completed_response),
        },
      })
      events
    }
  }
}

///|
fn emit_responses_output_item_events(
  events : Array[@sse.SseEvent],
  item : Json,
  output_index : Int,
) -> Unit {
  let output_index_json = Json::number(output_index.to_double())
  events.push({
    event: "response.output_item.added",
    data: {
      "type": "response.output_item.added",
      "output_index": output_index_json,
      "item": item,
    },
  })
  match item {
    { "type": String("message"), "content": Array(contents), .. } =>
      emit_responses_message_content_events(events, contents, output_index)
    { "type": String("function_call"), "arguments": String(arguments), .. } =>
      emit_responses_function_call_events(events, item, arguments, output_index)
    {
      "type": String("web_search_call"),
      "id": String(item_id),
      "status": String(status),
      ..
    } =>
      emit_responses_web_search_status_event(
        events, item_id, status, output_index,
      )
    _ => ()
  }
  events.push({
    event: "response.output_item.done",
    data: {
      "type": "response.output_item.done",
      "output_index": output_index_json,
      "item": item,
    },
  })
}

///|
fn emit_responses_message_content_events(
  events : Array[@sse.SseEvent],
  contents : Array[Json],
  output_index : Int,
) -> Unit {
  let output_index_json = Json::number(output_index.to_double())
  for content_index in 0..<contents.length() {
    match contents[content_index] {
      {
        "type": String("output_text"),
        "text": String(text),
        "annotations": Array(annotations),
        ..
      } => {
        let content_index_json = Json::number(content_index.to_double())
        if text.length() > 0 {
          events.push({
            event: "response.output_text.delta",
            data: {
              "type": "response.output_text.delta",
              "delta": text,
              "content_index": content_index_json,
              "output_index": output_index_json,
            },
          })
        }
        for annotation in annotations {
          events.push({
            event: "response.output_text.annotation.added",
            data: {
              "type": "response.output_text.annotation.added",
              "annotation": annotation,
              "content_index": content_index_json,
              "output_index": output_index_json,
            },
          })
        }
        events.push({
          event: "response.output_text.done",
          data: {
            "type": "response.output_text.done",
            "text": text,
            "content_index": content_index_json,
            "output_index": output_index_json,
          },
        })
      }
      _ => ()
    }
  }
}

///|
fn emit_responses_function_call_events(
  events : Array[@sse.SseEvent],
  item : Json,
  arguments : String,
  output_index : Int,
) -> Unit {
  let output_index_json = Json::number(output_index.to_double())
  let item_id = match item {
    { "call_id": String(call_id), .. } => call_id
    { "id": String(id), .. } => id
    _ => ""
  }
  if arguments.length() > 0 {
    events.push({
      event: "response.function_call_arguments.delta",
      data: {
        "type": "response.function_call_arguments.delta",
        "delta": arguments,
        "item_id": item_id,
        "output_index": output_index_json,
      },
    })
  }
  events.push({
    event: "response.function_call_arguments.done",
    data: {
      "type": "response.function_call_arguments.done",
      "arguments": arguments,
      "item_id": item_id,
      "output_index": output_index_json,
    },
  })
}

///|
fn emit_responses_web_search_status_event(
  events : Array[@sse.SseEvent],
  item_id : String,
  status : String,
  output_index : Int,
) -> Unit {
  let output_index_json = Json::number(output_index.to_double())
  let event = match status {
    "in_progress" => Some("response.web_search_call.in_progress")
    "searching" => Some("response.web_search_call.searching")
    "completed" => Some("response.web_search_call.completed")
    _ => None
  }
  match event {
    Some(event_name) =>
      events.push({
        event: event_name,
        data: {
          "type": event_name,
          "item_id": item_id,
          "output_index": output_index_json,
        },
      })
    None => ()
  }
}
