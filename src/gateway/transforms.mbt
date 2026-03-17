///|
/// Transform request body between gateway surface dialects
pub fn transform_request(
  body : String,
  from : GatewaySurface,
  to : GatewaySurface,
  model : String,
) -> String {
  match (from, to) {
    (OpenAI, OpenAI) | (Anthropic, Anthropic) | (Gemini, Gemini) => body
    (Anthropic, OpenAI) => @anthropic.anthropic_request_to_chat(body)
    (Gemini, OpenAI) => @gemini.gemini_request_to_chat(body, model)
    (OpenAI, Anthropic) => @anthropic.chat_request_to_anthropic(body)
    (Gemini, Anthropic) => {
      let openai = @gemini.gemini_request_to_chat(body, model)
      @anthropic.chat_request_to_anthropic(openai)
    }
    (OpenAI, Gemini) => @gemini.chat_request_to_gemini(body)
    (Anthropic, Gemini) => {
      let openai = @anthropic.anthropic_request_to_chat(body)
      @gemini.chat_request_to_gemini(openai)
    }
  }
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
          OpenAI => @anthropic.anthropic_error_to_openai(error_obj)
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
      OpenAI => body
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
  }
}
