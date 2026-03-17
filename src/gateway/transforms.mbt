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
    (Anthropic, OpenAI) => @anthropic.anthropic_request_to_chat(body, ctx)
    (Gemini, OpenAI) => @gemini.gemini_request_to_chat(body, model, ctx)
    (OpenAI, Anthropic) => @anthropic.chat_request_to_anthropic(body, ctx)
    (Gemini, Anthropic) => {
      let openai = @gemini.gemini_request_to_chat(body, model, ctx)
      @anthropic.chat_request_to_anthropic(openai, ctx)
    }
    (OpenAI, Gemini) => @gemini.chat_request_to_gemini(body, ctx)
    (Anthropic, Gemini) => {
      let openai = @anthropic.anthropic_request_to_chat(body, ctx)
      @gemini.chat_request_to_gemini(openai, ctx)
    }
    // Codex: extract prompt from any surface via OpenAI pivot
    (OpenAI, Codex) => @codex.chat_request_to_codex(body, ctx)
    (Anthropic, Codex) => {
      let openai = @anthropic.anthropic_request_to_chat(body, ctx)
      @codex.chat_request_to_codex(openai, ctx)
    }
    (Gemini, Codex) => {
      let openai = @gemini.gemini_request_to_chat(body, model, ctx)
      @codex.chat_request_to_codex(openai, ctx)
    }
    (Codex, OpenAI) | (Codex, Anthropic) | (Codex, Gemini) => body
    (Codex, Codex) => body
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
  let json = @json.parse(body) catch { _ => return body }
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
    _ => body
  }
}

///|
/// Normalize Anthropic request parameters using model config.
/// Ensures max_tokens is present (required field).
fn normalize_anthropic_params(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object(obj) => {
      if !obj.contains("max_tokens") && ctx.max_tokens > 0 {
        obj["max_tokens"] = Json::number(ctx.max_tokens.to_double())
        return Json::object(obj).stringify()
      }
      body
    }
    _ => body
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
pub fn transform_response(
  body : String,
  from : GatewaySurface,
  to : GatewaySurface,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Check for errors first
  if @anthropic.is_anthropic_error(json) {
    return match @anthropic.extract_anthropic_error(json) {
      Some(error_obj) =>
        match to {
          OpenAI | Codex => @anthropic.anthropic_error_to_openai(error_obj)
          Gemini => @anthropic.anthropic_error_to_gemini(error_obj)
          Anthropic => body
        }
      None => body
    }
  }
  if @anthropic.is_openai_error(json) {
    return match to {
      Anthropic => @anthropic.openai_error_to_anthropic(body)
      Gemini => @gemini.openai_error_to_gemini(body)
      OpenAI | Codex => body
    }
  }
  // Transform success response
  match (from, to) {
    (OpenAI, OpenAI) | (Anthropic, Anthropic) | (Gemini, Gemini) => body
    (Anthropic, OpenAI) => @anthropic.anthropic_response_to_chat(body)
    (Gemini, OpenAI) => @gemini.gemini_response_to_chat(body)
    (OpenAI, Anthropic) => @anthropic.chat_response_to_anthropic(body)
    (Gemini, Anthropic) => {
      let openai = @gemini.gemini_response_to_chat(body)
      @anthropic.chat_response_to_anthropic(openai)
    }
    (OpenAI, Gemini) => @gemini.chat_response_to_gemini(body)
    (Anthropic, Gemini) => {
      let openai = @anthropic.anthropic_response_to_chat(body)
      @gemini.chat_response_to_gemini(openai)
    }
    // Codex: events → target surface via OpenAI pivot
    (Codex, OpenAI) => @codex.codex_response_to_chat(body)
    (Codex, Anthropic) => {
      let openai = @codex.codex_response_to_chat(body)
      @anthropic.chat_response_to_anthropic(openai)
    }
    (Codex, Gemini) => {
      let openai = @codex.codex_response_to_chat(body)
      @gemini.chat_response_to_gemini(openai)
    }
    (OpenAI, Codex) | (Anthropic, Codex) | (Gemini, Codex) => body
    (Codex, Codex) => body
  }
}
