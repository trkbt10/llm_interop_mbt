///|
/// Tool Call ID format definitions and conversions between providers
///
/// Each LLM provider uses different ID formats for tool calls:
/// - OpenAI Chat Completions: `call_<suffix>`
/// - OpenAI Responses API: `fc_<suffix>`
/// - Anthropic Claude: `toolu_<suffix>`
/// - Google Gemini: No native ID (uses name-based reference, we generate `gemini_<name>_<index>`)

// =============================================================================
// Tool Call ID Format Definition
// =============================================================================

///|
/// Tool call ID format specification for each provider
pub(all) struct ToolCallIdFormat {
  /// Provider identifier
  provider : ToolCallIdProvider
  /// ID prefix (e.g., "call_", "toolu_")
  prefix : String
  /// Whether this provider natively supports IDs
  has_native_id : Bool
}

///|
/// Provider enum for tool call ID management
pub(all) enum ToolCallIdProvider {
  /// OpenAI Chat Completions API (call_xxx)
  OpenAIChatCompletions
  /// OpenAI Responses API (fc_xxx)
  OpenAIResponsesApi
  /// Anthropic Claude Messages API (toolu_xxx)
  AnthropicClaude
  /// Google Gemini GenerateContent API (gemini_xxx - synthetic)
  GoogleGemini
  /// Unknown provider
  Unknown
} derive(Eq, Show)

///|
/// Get the format specification for a provider
pub fn ToolCallIdProvider::format(
  self : ToolCallIdProvider,
) -> ToolCallIdFormat {
  match self {
    OpenAIChatCompletions =>
      { provider: OpenAIChatCompletions, prefix: "call_", has_native_id: true }
    OpenAIResponsesApi =>
      { provider: OpenAIResponsesApi, prefix: "fc_", has_native_id: true }
    AnthropicClaude =>
      { provider: AnthropicClaude, prefix: "toolu_", has_native_id: true }
    GoogleGemini =>
      { provider: GoogleGemini, prefix: "gemini_", has_native_id: false }
    Unknown => { provider: Unknown, prefix: "", has_native_id: false }
  }
}

///|
/// Get the prefix for a provider
pub fn ToolCallIdProvider::prefix(self : ToolCallIdProvider) -> String {
  self.format().prefix
}

// =============================================================================
// Provider Detection
// =============================================================================

///|
/// Detect the provider from a tool call ID string
pub fn detect_tool_call_id_provider(id : String) -> ToolCallIdProvider {
  // Check prefixes in order of specificity
  if id.has_prefix(ToolCallIdProvider::OpenAIChatCompletions.prefix()) {
    ToolCallIdProvider::OpenAIChatCompletions
  } else if id.has_prefix(ToolCallIdProvider::OpenAIResponsesApi.prefix()) {
    ToolCallIdProvider::OpenAIResponsesApi
  } else if id.has_prefix(ToolCallIdProvider::AnthropicClaude.prefix()) {
    ToolCallIdProvider::AnthropicClaude
  } else if id.has_prefix(ToolCallIdProvider::GoogleGemini.prefix()) {
    ToolCallIdProvider::GoogleGemini
  } else {
    ToolCallIdProvider::Unknown
  }
}

// =============================================================================
// ID Suffix Extraction
// =============================================================================

///|
/// Extract the unique suffix from a tool call ID (part after the first underscore)
fn extract_tool_call_id_suffix(id : String) -> String {
  let chars = id.iter().collect()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '_' {
      let sb = StringBuilder::new()
      for j = i + 1; j < chars.length(); j = j + 1 {
        sb.write_char(chars[j])
      }
      return sb.to_string()
    }
  }
  id
}

// =============================================================================
// ID Conversion Functions
// =============================================================================

///|
/// Convert a tool call ID to the specified target provider format
pub fn convert_tool_call_id_to(
  id : String,
  target : ToolCallIdProvider,
) -> String {
  let suffix = extract_tool_call_id_suffix(id)
  let target_prefix = target.prefix()
  "\{target_prefix}\{suffix}"
}

// --- OpenAI Chat Completions conversions ---

///|
/// Convert Anthropic Claude tool use ID to OpenAI Chat Completions call ID
/// `toolu_xxx` -> `call_xxx`
pub fn anthropic_to_openai_chat_call_id(claude_id : String) -> String {
  convert_tool_call_id_to(claude_id, ToolCallIdProvider::OpenAIChatCompletions)
}

///|
/// Convert OpenAI Responses API function call ID to OpenAI Chat Completions call ID
/// `fc_xxx` -> `call_xxx`
pub fn openai_responses_to_openai_chat_call_id(fc_id : String) -> String {
  convert_tool_call_id_to(fc_id, ToolCallIdProvider::OpenAIChatCompletions)
}

///|
/// Convert Google Gemini synthetic ID to OpenAI Chat Completions call ID
/// `gemini_xxx` -> `call_xxx`
pub fn gemini_to_openai_chat_call_id(gemini_id : String) -> String {
  convert_tool_call_id_to(gemini_id, ToolCallIdProvider::OpenAIChatCompletions)
}

// --- OpenAI Responses API conversions ---

///|
/// Convert Anthropic Claude tool use ID to OpenAI Responses API function call ID
/// `toolu_xxx` -> `fc_xxx`
pub fn anthropic_to_openai_responses_call_id(claude_id : String) -> String {
  convert_tool_call_id_to(claude_id, ToolCallIdProvider::OpenAIResponsesApi)
}

///|
/// Convert OpenAI Chat Completions call ID to OpenAI Responses API function call ID
/// `call_xxx` -> `fc_xxx`
pub fn openai_chat_to_openai_responses_call_id(call_id : String) -> String {
  convert_tool_call_id_to(call_id, ToolCallIdProvider::OpenAIResponsesApi)
}

///|
/// Convert Google Gemini synthetic ID to OpenAI Responses API function call ID
/// `gemini_xxx` -> `fc_xxx`
pub fn gemini_to_openai_responses_call_id(gemini_id : String) -> String {
  convert_tool_call_id_to(gemini_id, ToolCallIdProvider::OpenAIResponsesApi)
}

// --- Anthropic Claude conversions ---

///|
/// Convert OpenAI Chat Completions call ID to Anthropic Claude tool use ID
/// `call_xxx` -> `toolu_xxx`
pub fn openai_chat_to_anthropic_tool_use_id(call_id : String) -> String {
  convert_tool_call_id_to(call_id, ToolCallIdProvider::AnthropicClaude)
}

///|
/// Convert OpenAI Responses API function call ID to Anthropic Claude tool use ID
/// `fc_xxx` -> `toolu_xxx`
pub fn openai_responses_to_anthropic_tool_use_id(fc_id : String) -> String {
  convert_tool_call_id_to(fc_id, ToolCallIdProvider::AnthropicClaude)
}

///|
/// Convert Google Gemini synthetic ID to Anthropic Claude tool use ID
/// `gemini_xxx` -> `toolu_xxx`
pub fn gemini_to_anthropic_tool_use_id(gemini_id : String) -> String {
  convert_tool_call_id_to(gemini_id, ToolCallIdProvider::AnthropicClaude)
}

// --- Google Gemini conversions ---

///|
/// Convert OpenAI Chat Completions call ID to Google Gemini synthetic ID
/// `call_xxx` -> `gemini_xxx`
pub fn openai_chat_to_gemini_id(call_id : String) -> String {
  convert_tool_call_id_to(call_id, ToolCallIdProvider::GoogleGemini)
}

///|
/// Convert Anthropic Claude tool use ID to Google Gemini synthetic ID
/// `toolu_xxx` -> `gemini_xxx`
pub fn anthropic_to_gemini_id(claude_id : String) -> String {
  convert_tool_call_id_to(claude_id, ToolCallIdProvider::GoogleGemini)
}

// =============================================================================
// ID Comparison
// =============================================================================

///|
/// Check if two tool call IDs refer to the same call (ignoring provider prefixes)
pub fn is_same_tool_call_id(id1 : String, id2 : String) -> Bool {
  extract_tool_call_id_suffix(id1) == extract_tool_call_id_suffix(id2)
}

// =============================================================================
// ID Generation
// =============================================================================

///|
/// Counter for generating unique IDs
let tool_call_id_counter : Ref[Int] = Ref::new(0)

///|
/// Generate a new tool call ID for the specified provider
pub fn generate_tool_call_id(provider : ToolCallIdProvider) -> String {
  tool_call_id_counter.val = tool_call_id_counter.val + 1
  let prefix = provider.prefix()
  "\{prefix}\{tool_call_id_counter.val}"
}

///|
/// Generate a new OpenAI Chat Completions call ID (`call_xxx`)
pub fn generate_openai_chat_call_id() -> String {
  generate_tool_call_id(ToolCallIdProvider::OpenAIChatCompletions)
}

///|
/// Generate a new OpenAI Responses API function call ID (`fc_xxx`)
pub fn generate_openai_responses_call_id() -> String {
  generate_tool_call_id(ToolCallIdProvider::OpenAIResponsesApi)
}

///|
/// Generate a new Anthropic Claude tool use ID (`toolu_xxx`)
pub fn generate_anthropic_tool_use_id() -> String {
  generate_tool_call_id(ToolCallIdProvider::AnthropicClaude)
}

///|
/// Generate a Google Gemini synthetic ID from tool name and index
/// Format: `gemini_<name>_<index>`
pub fn generate_gemini_tool_call_id(
  tool_name : String,
  call_index : Int,
) -> String {
  let prefix = ToolCallIdProvider::GoogleGemini.prefix()
  "\{prefix}\{tool_name}_\{call_index}"
}

///|
/// Reset the ID counter (for testing purposes)
pub fn reset_tool_call_id_counter() -> Unit {
  tool_call_id_counter.val = 0
}

// =============================================================================
// Batch Conversion for Messages
// =============================================================================

///|
/// Convert all tool call IDs in a request array to target provider format
pub fn convert_tool_call_request_ids(
  requests : Array[@types.ToolCallRequest],
  target : ToolCallIdProvider,
) -> Array[@types.ToolCallRequest] {
  requests.map(fn(req) {
    let converted_id = convert_tool_call_id_to(req.id, target)
    @types.ToolCallRequest::new(
      id=converted_id,
      name=req.name,
      arguments=req.arguments,
    )
  })
}

///|
/// Convert all tool call IDs in message array to target provider format
pub fn convert_message_tool_call_ids(
  messages : Array[@types.ModelMessage],
  target : ToolCallIdProvider,
) -> Array[@types.ModelMessage] {
  messages.map(fn(msg) {
    match msg {
      @types.ModelMessage::Assistant(content~, tool_calls~) =>
        match tool_calls {
          Some(calls) =>
            @types.ModelMessage::Assistant(
              content~,
              tool_calls=Some(convert_tool_call_request_ids(calls, target)),
            )
          None => msg
        }
      @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
        @types.ModelMessage::ToolResult(
          tool_call_id=convert_tool_call_id_to(tool_call_id, target),
          content~,
        )
      _ => msg
    }
  })
}
