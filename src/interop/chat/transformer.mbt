///|
/// Unified transformer for Chat Completions API gateway
///
/// Provides high-level transformation functions that route based on
/// source and target dialect.

///|
/// Dialect identifier
pub(all) enum Dialect {
  OpenAI
  Anthropic
  Gemini
} derive(Show)

///|
/// Transform request from source dialect to target dialect
pub fn transform_request(
  body : String,
  from : Dialect,
  to : Dialect,
  model : String,
) -> String {
  match (from, to) {
    // Same dialect - passthrough
    (OpenAI, OpenAI) => body
    (Anthropic, Anthropic) => body
    (Gemini, Gemini) => body
    // To OpenAI
    (Anthropic, OpenAI) => anthropic_request_to_chat(body)
    (Gemini, OpenAI) => gemini_request_to_chat(body, model)
    // To Anthropic
    (OpenAI, Anthropic) => chat_request_to_anthropic(body)
    (Gemini, Anthropic) => {
      let openai = gemini_request_to_chat(body, model)
      chat_request_to_anthropic(openai)
    }
    // To Gemini
    (OpenAI, Gemini) => chat_request_to_gemini(body)
    (Anthropic, Gemini) => {
      let openai = anthropic_request_to_chat(body)
      chat_request_to_gemini(openai)
    }
  }
}

///|
/// Transform response from source dialect to target dialect
/// Handles both success and error responses
pub fn transform_response(
  body : String,
  from : Dialect,
  to : Dialect,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Check for errors first
  if is_anthropic_error(json) {
    return match extract_anthropic_error(json) {
      Some(error_obj) =>
        match to {
          OpenAI => anthropic_error_to_openai(error_obj)
          Gemini => anthropic_error_to_gemini(error_obj)
          Anthropic => body
        }
      None => body
    }
  }
  if is_openai_error(json) {
    return match to {
      Anthropic => openai_error_to_anthropic(body)
      Gemini => openai_error_to_gemini(body)
      OpenAI => body
    }
  }
  // Transform success response
  match (from, to) {
    // Same dialect - passthrough
    (OpenAI, OpenAI) => body
    (Anthropic, Anthropic) => body
    (Gemini, Gemini) => body
    // To OpenAI
    (Anthropic, OpenAI) => anthropic_response_to_chat(body)
    (Gemini, OpenAI) => gemini_response_to_chat(body)
    // To Anthropic
    (OpenAI, Anthropic) => chat_response_to_anthropic(body)
    (Gemini, Anthropic) => {
      let openai = gemini_response_to_chat(body)
      chat_response_to_anthropic(openai)
    }
    // To Gemini
    (OpenAI, Gemini) => chat_response_to_gemini(body)
    (Anthropic, Gemini) => {
      let openai = anthropic_response_to_chat(body)
      chat_response_to_gemini(openai)
    }
  }
}
