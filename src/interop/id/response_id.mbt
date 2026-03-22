///|
/// Response ID format definitions and generation
///
/// LLM providers use different ID formats for responses:
/// - OpenAI Chat Completions: `chatcmpl-<suffix>`
/// - OpenAI Responses API: `resp-<suffix>`
/// - Anthropic Claude: `msg_<suffix>`
/// - Google Gemini: no native response ID (synthetic `gemini-resp-<model>`)
///
/// Follows the same pattern as tool_call_id.mbt.

// =============================================================================
// Response ID Format Definition
// =============================================================================

///|
/// Response ID format specification for each provider
pub(all) struct ResponseIdFormat {
  provider : ResponseIdProvider
  prefix : String
  has_native_id : Bool
}

///|
/// Provider enum for response ID management
pub(all) enum ResponseIdProvider {
  /// OpenAI Chat Completions API (chatcmpl-xxx)
  OpenAIChatCompletions
  /// OpenAI Responses API (resp-xxx / resp_xxx)
  OpenAIResponsesApi
  /// Anthropic Claude Messages API (msg_xxx)
  AnthropicClaude
  /// Google Gemini GenerateContent API (no native ID)
  GoogleGemini
  /// Unknown provider
  Unknown
} derive(Eq, Show)

///|
/// Get the format specification for a provider
pub fn ResponseIdProvider::format(
  self : ResponseIdProvider,
) -> ResponseIdFormat {
  match self {
    OpenAIChatCompletions =>
      {
        provider: OpenAIChatCompletions,
        prefix: "chatcmpl-",
        has_native_id: true,
      }
    OpenAIResponsesApi =>
      { provider: OpenAIResponsesApi, prefix: "resp_", has_native_id: true }
    AnthropicClaude =>
      { provider: AnthropicClaude, prefix: "msg_", has_native_id: true }
    GoogleGemini =>
      { provider: GoogleGemini, prefix: "gemini-resp-", has_native_id: false }
    Unknown => { provider: Unknown, prefix: "resp_", has_native_id: false }
  }
}

///|
/// Get the prefix for a provider
pub fn ResponseIdProvider::prefix(self : ResponseIdProvider) -> String {
  self.format().prefix
}

// =============================================================================
// Provider Detection
// =============================================================================

///|
/// Detect the provider from a response ID string
pub fn detect_response_id_provider(id : String) -> ResponseIdProvider {
  if id.has_prefix(ResponseIdProvider::OpenAIChatCompletions.prefix()) {
    ResponseIdProvider::OpenAIChatCompletions
  } else if id.has_prefix(ResponseIdProvider::AnthropicClaude.prefix()) {
    ResponseIdProvider::AnthropicClaude
  } else if id.has_prefix(ResponseIdProvider::GoogleGemini.prefix()) {
    ResponseIdProvider::GoogleGemini
  } else if id.has_prefix(ResponseIdProvider::OpenAIResponsesApi.prefix()) {
    ResponseIdProvider::OpenAIResponsesApi
  } else {
    ResponseIdProvider::Unknown
  }
}

// =============================================================================
// ID Generation
// =============================================================================

///|
/// Counter for generating unique response IDs
let response_id_counter : Ref[Int] = Ref::new(0)

///|
/// Generate a fallback response ID for the specified provider
pub fn generate_response_id(provider : ResponseIdProvider) -> String {
  response_id_counter.val = response_id_counter.val + 1
  let prefix = provider.prefix()
  "\{prefix}\{response_id_counter.val}"
}

///|
/// Generate a fallback response ID with a model name suffix
pub fn generate_response_id_for_model(
  provider : ResponseIdProvider,
  model : String,
) -> String {
  let prefix = provider.prefix()
  "\{prefix}\{model}"
}

///|
/// Reset the response ID counter (for testing purposes)
pub fn reset_response_id_counter() -> Unit {
  response_id_counter.val = 0
}

// =============================================================================
// Extraction
// =============================================================================

///|
/// Extract response ID from a JSON response body.
/// Looks for "id" field. Returns None if not found or parse fails.
pub fn extract_response_id_from_json(body : String) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  match json {
    { "id": String(id), .. } => Some(id)
    _ => None
  }
}

///|
/// Extract response ID from a JSON response body, with fallback generation.
pub fn extract_or_generate_response_id(
  body : String,
  provider : ResponseIdProvider,
  model : String,
) -> String {
  match extract_response_id_from_json(body) {
    Some(id) => id
    None => generate_response_id_for_model(provider, model)
  }
}
