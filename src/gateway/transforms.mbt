///|
/// Transform request body between gateway surface dialects
pub fn transform_request(
  body : String,
  from : GatewaySurface,
  to : GatewaySurface,
  model : String,
  ctx : @types.TransformContext,
) -> String {
  match (from, to) {
    (OpenAI, OpenAI) => normalize_openai_params(body, ctx)
    (Anthropic, Anthropic) => normalize_anthropic_params(body, ctx)
    (Gemini, Gemini) => normalize_gemini_params(body, ctx)
    (Anthropic, OpenAI)
    | (Gemini, OpenAI)
    | (OpenAI, Anthropic)
    | (Gemini, Anthropic)
    | (OpenAI, Gemini)
    | (Anthropic, Gemini)
    | (OpenAI, Codex)
    | (Anthropic, Codex)
    | (Gemini, Codex) =>
      responses_request_to_gateway_surface(
        request_body_to_responses_request(body, from, model, ctx),
        to,
        ctx,
      )
    (Codex, OpenAI) | (Codex, Anthropic) | (Codex, Gemini) =>
      responses_request_to_gateway_surface(
        request_body_to_responses_request(body, from, model, ctx),
        to,
        ctx,
      )
    (Codex, Codex) => body
  }
}

///|
fn request_body_to_responses_request(
  body : String,
  from : GatewaySurface,
  model : String,
  ctx : @types.TransformContext,
) -> Json {
  match from {
    OpenAI => @openai_chat_contract.chat_request_to_responses_request(body)
    Codex =>
      @openai_chat_contract.chat_request_to_responses_request(
        @codex.protocol_request_to_chat(body),
      )
    Anthropic =>
      @openai_chat_contract.chat_request_to_responses_request(
        @anthropic.request_to_chat(body, ctx),
      )
    Gemini =>
      @openai_chat_contract.chat_request_to_responses_request(
        @gemini.request_to_chat(body, model, ctx),
      )
  }
}

///|
fn responses_request_stream_flag(request : Json) -> Bool {
  match request {
    { "stream": True, .. } => true
    _ => false
  }
}

///|
fn responses_request_to_gateway_surface(
  request : Json,
  to : GatewaySurface,
  ctx : @types.TransformContext,
) -> String {
  match to {
    OpenAI =>
      @harmony.responses_request_to_chat_completions(
        request,
        stream=responses_request_stream_flag(request),
      ).stringify()
    Anthropic =>
      if responses_request_stream_flag(request) {
        @anthropic.responses_request_to_anthropic_stream(request).stringify()
      } else {
        @anthropic.responses_request_to_anthropic(request).stringify()
      }
    Gemini => @gemini.responses_request_to_gemini(request).stringify()
    Codex => {
      let chat = @harmony.responses_request_to_chat_completions(
        request,
        stream=false,
      )
      @codex.chat_request_to_protocol(chat.stringify(), ctx)
    }
  }
}

///|
/// Normalize OpenAI request parameters using model config.
/// Handles max_tokens_field renaming (e.g. max_tokens → max_completion_tokens for o1).
fn normalize_openai_params(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  if ctx.max_tokens_field == "max_tokens" {
    return body
  }
  let json = @json.parse(body) catch {
    _ =>
      abort(
        "Gateway OpenAI same-surface normalization requires a JSON object request body: " +
        body,
      )
  }
  match json {
    Object(obj) => {
      // Rename max_tokens to the model's expected field name
      match obj.get("max_tokens") {
        Some(val) if !obj.contains(ctx.max_tokens_field) => {
          obj.remove("max_tokens")
          obj[ctx.max_tokens_field] = val
        }
        _ => ()
      }
      Json::object(obj).stringify()
    }
    _ =>
      abort(
        "Gateway OpenAI same-surface normalization requires a JSON object request body: " +
        body,
      )
  }
}

///|
/// Normalize Anthropic request parameters using model config.
/// Ensures max_tokens is present (required field).
fn normalize_anthropic_params(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch {
    _ =>
      abort(
        "Gateway Anthropic same-surface normalization requires a JSON object request body: " +
        body,
      )
  }
  match json {
    Object(obj) => {
      if !obj.contains("max_tokens") && ctx.max_tokens > 0 {
        obj["max_tokens"] = Json::number(ctx.max_tokens.to_double())
        return Json::object(obj).stringify()
      }
      body
    }
    _ =>
      abort(
        "Gateway Anthropic same-surface normalization requires a JSON object request body: " +
        body,
      )
  }
}

///|
/// Normalize Gemini request parameters using model config.
/// No normalization needed currently — Gemini field names are stable.
fn normalize_gemini_params(
  body : String,
  _ctx : @types.TransformContext,
) -> String {
  body
}

///|
/// Transform response body between gateway surface dialects
/// Handles both success and error responses
///
/// Note: the success-response path below pivots through chat-shaped dialect
/// transforms. That preserves text/tool-call semantics and the official
/// OpenAI Chat `url_citation` subset. Provider-specific annotation families
/// without a target-surface carrier are rejected here rather than silently
/// degraded. Full annotation-preserving interop must use the Responses
/// pipeline in `responses_pipeline.mbt`.
pub fn transform_response(
  body : String,
  from : GatewaySurface,
  to : GatewaySurface,
) -> String {
  match (from, to) {
    (OpenAI, OpenAI) | (Anthropic, Anthropic) | (Gemini, Gemini) => body
    (Anthropic, OpenAI)
    | (Gemini, OpenAI)
    | (OpenAI, Anthropic)
    | (Gemini, Anthropic)
    | (OpenAI, Gemini)
    | (Anthropic, Gemini)
    | (Codex, OpenAI)
    | (Codex, Anthropic)
    | (Codex, Gemini)
    | (OpenAI, Codex)
    | (Anthropic, Codex)
    | (Gemini, Codex) =>
      responses_json_to_gateway_surface(
        source_response_to_responses_json(body, from),
        to,
      )
    (Codex, Codex) => body
  }
}

///|
fn source_response_to_responses_json(
  body : String,
  from : GatewaySurface,
) -> Json {
  let source_body = match from {
    Codex => @codex.response_to_chat(body)
    _ => body
  }
  let source_json = @json.parse(source_body) catch {
    _ =>
      abort(
        "Gateway response translation requires a JSON response body: " +
        source_body,
      )
  }
  let source_api = match from {
    OpenAI => OpenAICompletions
    Anthropic => AnthropicMessages
    Gemini => GoogleGenerativeAI
    Codex => OpenAICompletions
  }
  let model = @utils.extract_json_field(source_body, "model").unwrap_or("")
  match (from, source_json) {
    (Anthropic, { "type": String("error"), .. } as json) =>
      return failure_response_to_responses_json(
        parse_openai_error_response(
          @anthropic.error_to_openai(
            match @anthropic.extract_error(json) {
              Some(error_obj) => error_obj
              None => json
            },
          ),
        ),
        model,
      )
    (Gemini, json) if @gemini.is_error(json) =>
      return failure_response_to_responses_json(
        parse_openai_error_response(
          @gemini.error_to_openai(
            match json {
              { "error": error_obj, .. } => error_obj
              _ => json
            },
          ),
        ),
        model,
      )
    (OpenAI, json) if @anthropic.is_openai_error(json) =>
      return failure_response_to_responses_json(
        @openai.parse_chat_response(json),
        model,
      )
    _ => ()
  }
  transform_response_to_responses_json(source_api, source_body, model~)
}

///|
fn parse_openai_error_response(body : String) -> @types.ModelResponse {
  let json = @json.parse(body) catch {
    _ =>
      return @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="JSON parse error",
          body=Some(body),
        ),
      )
  }
  @openai.parse_chat_response(json)
}

///|
fn failure_response_to_responses_json(
  response : @types.ModelResponse,
  model : String,
) -> Json {
  @openai_responses_contract.model_response_to_responses_json(
    match response.as_failure() {
      Some(_) => response
      None =>
        @types.ModelResponse::Failure(
          failure=@types.ModelFailure::new(
            type_="api_error",
            message="Expected failure response during gateway error translation",
          ),
        )
    },
    response_id=fallback_response_id(model),
    model~,
  )
}

///|
fn responses_json_to_gateway_surface(
  responses_json : Json,
  to : GatewaySurface,
) -> String {
  let parsed = @openai.parse_responses_api_response(responses_json)
  let id = match responses_json {
    { "id": String(value), .. } => value
    _ => "chatcmpl_interop"
  }
  let model = match responses_json {
    { "model": String(value), .. } => value
    _ => ""
  }
  match to {
    OpenAI =>
      @openai_chat_contract.model_response_to_chat_response(parsed, id~, model~)
    Anthropic =>
      match parsed.as_failure() {
        Some(failure) => failure.to_anthropic_error_json().stringify()
        None =>
          @anthropic.chat_response_to_anthropic(
            @openai_chat_contract.model_response_to_chat_response(
              parsed,
              id~,
              model~,
            ),
          )
      }
    Gemini =>
      match parsed.as_failure() {
        Some(failure) => failure.to_gemini_error_json().stringify()
        None =>
          @gemini.chat_response_to_gemini(
            @openai_chat_contract.model_response_to_chat_response(
              parsed,
              id~,
              model~,
            ),
          )
      }
    Codex => responses_json_to_codex_response(parsed, id, model)
  }
}

///|
fn responses_json_to_codex_response(
  response : @types.ModelResponse,
  response_id : String,
  model : String,
) -> String {
  let chat_response = codex_compatible_chat_response(
    response, response_id, model,
  )
  let events = @codex.chat_response_to_events(
    chat_response,
    codex_bridge_id("thread", response_id),
    codex_bridge_id("turn", response_id),
    codex_bridge_id("item", response_id),
  )
  let event_json : Array[Json] = []
  for event in events {
    event_json.push(
      @json.parse(event) catch {
        _ =>
          abort("Codex response bridge generated invalid event JSON: " + event)
      },
    )
  }
  Json::array(event_json).stringify()
}

///|
fn codex_compatible_chat_response(
  response : @types.ModelResponse,
  response_id : String,
  model : String,
) -> String {
  match response.as_failure() {
    Some(_) =>
      return @openai_chat_contract.model_response_to_chat_response(
        response,
        id=response_id,
        model~,
      )
    None => ()
  }
  match response {
    @types.ModelResponse::Text(_) =>
      @openai_chat_contract.model_response_to_chat_response(
        response,
        id=response_id,
        model~,
      )
    @types.ModelResponse::RichText(rich) => {
      if rich.annotations.length() > 0 || rich.tool_traces.length() > 0 {
        abort(
          "Codex response bridge cannot represent annotations or tool traces without loss; use OpenAI/Responses surface instead",
        )
      }
      match rich.content_parts {
        Some(parts) =>
          for part in parts {
            match part {
              @types.ResponseContentPart::OutputText(_) => ()
              _ =>
                abort(
                  "Codex response bridge cannot represent non-text response content without loss; use OpenAI/Responses surface instead",
                )
            }
          }
        None => ()
      }
      @openai_chat_contract.model_response_to_chat_response(
        response,
        id=response_id,
        model~,
      )
    }
    _ =>
      abort(
        "Codex response bridge cannot represent tool-calling or non-text responses without loss; use OpenAI/Responses surface instead",
      )
  }
}

///|
fn codex_bridge_id(prefix : String, response_id : String) -> String {
  let suffix = if response_id.length() > 0 { response_id } else { "interop" }
  prefix + "_" + suffix
}
