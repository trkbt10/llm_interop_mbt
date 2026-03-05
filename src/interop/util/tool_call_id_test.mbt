///|
/// Tool call ID conversion tests
/// Ported from llm-interop TypeScript: adapters/conversation/id-conversion.spec.ts

// =============================================================================
// toOpenAICallIdFromClaude (anthropic_to_openai_chat_call_id)
// =============================================================================

test "anthropic_to_openai: converts Claude tool_use_id to OpenAI call_id format" {
  assert_eq(anthropic_to_openai_chat_call_id("toolu_01ABC123"), "call_01ABC123")
  assert_eq(anthropic_to_openai_chat_call_id("toolu_xyz789"), "call_xyz789")
}

///|
test "anthropic_to_openai: handles IDs without underscore" {
  assert_eq(anthropic_to_openai_chat_call_id("abc123"), "call_abc123")
  assert_eq(anthropic_to_openai_chat_call_id("simple"), "call_simple")
}

///|
test "anthropic_to_openai: handles empty string" {
  assert_eq(anthropic_to_openai_chat_call_id(""), "call_")
}

///|
test "anthropic_to_openai: handles IDs with multiple underscores" {
  assert_eq(
    anthropic_to_openai_chat_call_id("toolu_01_ABC_123"),
    "call_01_ABC_123",
  )
  assert_eq(
    anthropic_to_openai_chat_call_id("prefix_middle_suffix"),
    "call_middle_suffix",
  )
}

// =============================================================================
// toClaudeToolUseIdFromOpenAI (openai_chat_to_anthropic_tool_use_id)
// =============================================================================

///|
test "openai_to_anthropic: converts OpenAI call_id to Claude tool_use_id format" {
  assert_eq(
    openai_chat_to_anthropic_tool_use_id("call_01ABC123"),
    "toolu_01ABC123",
  )
  assert_eq(openai_chat_to_anthropic_tool_use_id("call_xyz789"), "toolu_xyz789")
}

///|
test "openai_to_anthropic: handles IDs without underscore" {
  assert_eq(openai_chat_to_anthropic_tool_use_id("abc123"), "toolu_abc123")
  assert_eq(openai_chat_to_anthropic_tool_use_id("simple"), "toolu_simple")
}

///|
test "openai_to_anthropic: handles empty string" {
  assert_eq(openai_chat_to_anthropic_tool_use_id(""), "toolu_")
}

///|
test "openai_to_anthropic: handles IDs with multiple underscores" {
  assert_eq(
    openai_chat_to_anthropic_tool_use_id("call_01_ABC_123"),
    "toolu_01_ABC_123",
  )
  assert_eq(
    openai_chat_to_anthropic_tool_use_id("prefix_middle_suffix"),
    "toolu_middle_suffix",
  )
}

// =============================================================================
// isSameIgnoringPrefix (is_same_tool_call_id)
// =============================================================================

///|
test "is_same: returns true for IDs with same suffix but different prefixes" {
  assert_true(is_same_tool_call_id("call_01ABC123", "toolu_01ABC123"))
  assert_true(is_same_tool_call_id("toolu_xyz789", "call_xyz789"))
  assert_true(is_same_tool_call_id("fc_123", "ws_123"))
}

///|
test "is_same: returns true for identical IDs" {
  assert_true(is_same_tool_call_id("call_01ABC123", "call_01ABC123"))
  assert_true(is_same_tool_call_id("toolu_xyz789", "toolu_xyz789"))
}

///|
test "is_same: returns false for different suffixes" {
  assert_false(is_same_tool_call_id("call_01ABC123", "call_01ABC124"))
  assert_false(is_same_tool_call_id("toolu_xyz789", "toolu_xyz788"))
}

///|
test "is_same: handles IDs without underscore" {
  assert_true(is_same_tool_call_id("abc123", "abc123"))
  assert_false(is_same_tool_call_id("abc123", "abc124"))
}

///|
test "is_same: handles empty strings" {
  assert_true(is_same_tool_call_id("", ""))
  assert_true(is_same_tool_call_id("call_", "toolu_"))
}

// =============================================================================
// Round-trip conversions
// =============================================================================

///|
test "roundtrip: preserves ID suffix through OpenAI -> Claude -> OpenAI" {
  let original_openai = "call_01ABC123"
  let to_claude = openai_chat_to_anthropic_tool_use_id(original_openai)
  let back_to_openai = anthropic_to_openai_chat_call_id(to_claude)
  assert_true(is_same_tool_call_id(original_openai, back_to_openai))
  assert_eq(back_to_openai, original_openai)
}

///|
test "roundtrip: preserves ID suffix through Claude -> OpenAI -> Claude" {
  let original_claude = "toolu_xyz789"
  let to_openai = anthropic_to_openai_chat_call_id(original_claude)
  let back_to_claude = openai_chat_to_anthropic_tool_use_id(to_openai)
  assert_true(is_same_tool_call_id(original_claude, back_to_claude))
  assert_eq(back_to_claude, original_claude)
}

// =============================================================================
// Responses API conversions
// =============================================================================

///|
test "anthropic_to_responses: converts Claude ID to Responses API format" {
  assert_eq(
    anthropic_to_openai_responses_call_id("toolu_01ABC123"),
    "fc_01ABC123",
  )
  assert_eq(anthropic_to_openai_responses_call_id("toolu_xyz789"), "fc_xyz789")
}

///|
test "gemini_to_responses: converts Gemini synthetic ID to Responses API format" {
  assert_eq(
    gemini_to_openai_responses_call_id("gemini_get_weather_0"),
    "fc_get_weather_0",
  )
}

///|
test "responses_to_anthropic: converts Responses API ID to Claude format" {
  assert_eq(
    openai_responses_to_anthropic_tool_use_id("fc_01ABC123"),
    "toolu_01ABC123",
  )
}

// =============================================================================
// Provider detection
// =============================================================================

///|
test "detect_provider: detects OpenAI Chat Completions format" {
  assert_eq(
    detect_tool_call_id_provider("call_01ABC123"),
    ToolCallIdProvider::OpenAIChatCompletions,
  )
}

///|
test "detect_provider: detects OpenAI Responses API format" {
  assert_eq(
    detect_tool_call_id_provider("fc_01ABC123"),
    ToolCallIdProvider::OpenAIResponsesApi,
  )
}

///|
test "detect_provider: detects Anthropic Claude format" {
  assert_eq(
    detect_tool_call_id_provider("toolu_01ABC123"),
    ToolCallIdProvider::AnthropicClaude,
  )
}

///|
test "detect_provider: detects Google Gemini format" {
  assert_eq(
    detect_tool_call_id_provider("gemini_get_weather_0"),
    ToolCallIdProvider::GoogleGemini,
  )
}

///|
test "detect_provider: returns Unknown for unrecognized format" {
  assert_eq(
    detect_tool_call_id_provider("unknown_123"),
    ToolCallIdProvider::Unknown,
  )
}

// =============================================================================
// Common ID patterns (from TypeScript tests)
// =============================================================================

///|
test "common_patterns: handles common Claude ID patterns" {
  let claude_patterns = [
    "toolu_01HX5SSXW9E8J4C8YPWPTFXW9V", "toolu_bdrk_01HsFH5fhkKzPa2tG5TmFgHh", "toolu_01234567890abcdefghijklmnop",
  ]
  for claude_id in claude_patterns {
    let openai_id = anthropic_to_openai_chat_call_id(claude_id)
    assert_true(openai_id.has_prefix("call_"))
    let back_to_claude = openai_chat_to_anthropic_tool_use_id(openai_id)
    assert_eq(back_to_claude, claude_id)
  }
}

///|
test "common_patterns: handles common OpenAI ID patterns" {
  let openai_patterns = ["call_abc123", "call_1234567890", "call_a1b2c3d4e5f6"]
  for openai_id in openai_patterns {
    let claude_id = openai_chat_to_anthropic_tool_use_id(openai_id)
    assert_true(claude_id.has_prefix("toolu_"))
    let back_to_openai = anthropic_to_openai_chat_call_id(claude_id)
    assert_eq(back_to_openai, openai_id)
  }
}

// =============================================================================
// Edge cases (from TypeScript tests)
// =============================================================================

///|
test "edge_cases: handles special characters in IDs" {
  assert_eq(
    anthropic_to_openai_chat_call_id("toolu_01-ABC.123"),
    "call_01-ABC.123",
  )
  assert_eq(
    openai_chat_to_anthropic_tool_use_id("call_xyz@789#"),
    "toolu_xyz@789#",
  )
}

///|
test "edge_cases: handles very long IDs" {
  let long_suffix = "a".repeat(100)
  let claude_id = "toolu_\{long_suffix}"
  let openai_id = anthropic_to_openai_chat_call_id(claude_id)
  assert_eq(openai_id, "call_\{long_suffix}")
  let back = openai_chat_to_anthropic_tool_use_id(openai_id)
  assert_eq(back, claude_id)
}

///|
test "edge_cases: handles unicode characters" {
  // Note: MoonBit handles unicode natively in strings
  assert_eq(
    anthropic_to_openai_chat_call_id("toolu_工具123"),
    "call_工具123",
  )
  assert_eq(
    openai_chat_to_anthropic_tool_use_id("call_测试789"),
    "toolu_测试789",
  )
}

///|
test "edge_cases: preserves unicode through roundtrip" {
  let original = "toolu_日本語テスト"
  let converted = anthropic_to_openai_chat_call_id(original)
  let back = openai_chat_to_anthropic_tool_use_id(converted)
  assert_eq(back, original)
}

// =============================================================================
// Cross-provider roundtrip (all 4 providers)
// =============================================================================

///|
test "cross_provider: Claude -> Chat -> Responses -> Claude preserves suffix" {
  let original = "toolu_crosstest123"
  let to_chat = anthropic_to_openai_chat_call_id(original)
  let to_responses = openai_chat_to_openai_responses_call_id(to_chat)
  let back_to_claude = openai_responses_to_anthropic_tool_use_id(to_responses)
  assert_true(is_same_tool_call_id(original, back_to_claude))
}

///|
test "cross_provider: Gemini -> Responses -> Chat -> Gemini preserves suffix" {
  let original = "gemini_my_tool_5"
  let to_responses = gemini_to_openai_responses_call_id(original)
  let to_chat = openai_responses_to_openai_chat_call_id(to_responses)
  let back_to_gemini = openai_chat_to_gemini_id(to_chat)
  assert_true(is_same_tool_call_id(original, back_to_gemini))
}
