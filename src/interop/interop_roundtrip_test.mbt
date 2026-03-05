///|
/// Interoperability round-trip tests
///
/// Tests that tool call ID conversions maintain consistency across all providers:
/// - OpenAI Chat Completions (call_xxx)
/// - OpenAI Responses API (fc_xxx)
/// - Anthropic Claude (toolu_xxx)
/// - Google Gemini (gemini_xxx)

// =============================================================================
// Test Fixtures: Realistic IDs from actual API responses
// =============================================================================

/// Anthropic Claude tool use ID (from actual API response)
let fixture_anthropic_tool_use_id : String = "toolu_017RLx2kgtjuhyb6yzCYoY4M"

/// OpenAI Responses API function call ID (from actual API response)
let fixture_openai_responses_fc_id : String = "fc_0f6e93c5cb6fbed40069a2579e9c688191925c675daa400bda"

/// OpenAI Responses API call_id (from actual API response)
let fixture_openai_responses_call_id : String = "call_eArLoUy4ikZiEzhId8UK1v2l"

/// Google Gemini synthetic ID (generated, since Gemini has no native IDs)
let fixture_gemini_synthetic_id : String = "gemini_get_weather_0"

// =============================================================================
// Provider Detection Tests
// =============================================================================

///|
test "detect_tool_call_id_provider: real Anthropic ID" {
  let provider = detect_tool_call_id_provider(fixture_anthropic_tool_use_id)
  match provider {
    ToolCallIdProvider::AnthropicClaude => ()
    _ => fail("Expected AnthropicClaude for toolu_ prefix")
  }
}

///|
test "detect_tool_call_id_provider: real OpenAI Responses fc_ ID" {
  let provider = detect_tool_call_id_provider(fixture_openai_responses_fc_id)
  match provider {
    ToolCallIdProvider::OpenAIResponsesApi => ()
    _ => fail("Expected OpenAIResponsesApi for fc_ prefix")
  }
}

///|
test "detect_tool_call_id_provider: real OpenAI Chat call_ ID" {
  let provider = detect_tool_call_id_provider(fixture_openai_responses_call_id)
  match provider {
    ToolCallIdProvider::OpenAIChatCompletions => ()
    _ => fail("Expected OpenAIChatCompletions for call_ prefix")
  }
}

///|
test "detect_tool_call_id_provider: real Gemini synthetic ID" {
  let provider = detect_tool_call_id_provider(fixture_gemini_synthetic_id)
  match provider {
    ToolCallIdProvider::GoogleGemini => ()
    _ => fail("Expected GoogleGemini for gemini_ prefix")
  }
}

// =============================================================================
// Round-trip Conversion Tests: A -> B -> A should preserve suffix
// =============================================================================

///|
test "roundtrip: Anthropic -> OpenAI Chat -> Anthropic preserves suffix" {
  let original = fixture_anthropic_tool_use_id
  let to_openai = anthropic_to_openai_chat_call_id(original)
  let back_to_anthropic = openai_chat_to_anthropic_tool_use_id(to_openai)
  // Suffix should be preserved
  assert_true(is_same_tool_call_id(original, back_to_anthropic))
  // Prefix should be correct
  assert_true(back_to_anthropic.has_prefix("toolu_"))
}

///|
test "roundtrip: Anthropic -> OpenAI Responses -> Anthropic preserves suffix" {
  let original = fixture_anthropic_tool_use_id
  let to_openai = anthropic_to_openai_responses_call_id(original)
  let back_to_anthropic = openai_responses_to_anthropic_tool_use_id(to_openai)
  assert_true(is_same_tool_call_id(original, back_to_anthropic))
  assert_true(back_to_anthropic.has_prefix("toolu_"))
}

///|
test "roundtrip: OpenAI Chat -> Anthropic -> OpenAI Chat preserves suffix" {
  let original = fixture_openai_responses_call_id
  let to_anthropic = openai_chat_to_anthropic_tool_use_id(original)
  let back_to_openai = anthropic_to_openai_chat_call_id(to_anthropic)
  assert_true(is_same_tool_call_id(original, back_to_openai))
  assert_true(back_to_openai.has_prefix("call_"))
}

///|
test "roundtrip: OpenAI Chat -> OpenAI Responses -> OpenAI Chat preserves suffix" {
  let original = fixture_openai_responses_call_id
  let to_responses = openai_chat_to_openai_responses_call_id(original)
  let back_to_chat = openai_responses_to_openai_chat_call_id(to_responses)
  assert_true(is_same_tool_call_id(original, back_to_chat))
  assert_true(back_to_chat.has_prefix("call_"))
}

///|
test "roundtrip: Gemini -> OpenAI Chat -> Gemini preserves suffix" {
  let original = fixture_gemini_synthetic_id
  let to_openai = gemini_to_openai_chat_call_id(original)
  let back_to_gemini = openai_chat_to_gemini_id(to_openai)
  assert_true(is_same_tool_call_id(original, back_to_gemini))
  assert_true(back_to_gemini.has_prefix("gemini_"))
}

///|
test "roundtrip: Gemini -> Anthropic -> Gemini preserves suffix" {
  let original = fixture_gemini_synthetic_id
  let to_anthropic = gemini_to_anthropic_tool_use_id(original)
  let back_to_gemini = anthropic_to_gemini_id(to_anthropic)
  assert_true(is_same_tool_call_id(original, back_to_gemini))
  assert_true(back_to_gemini.has_prefix("gemini_"))
}

// =============================================================================
// Cross-provider Equality Tests
// =============================================================================

///|
test "cross-provider equality: same suffix matches across all providers" {
  // Start with Anthropic ID
  let anthropic_id = fixture_anthropic_tool_use_id
  // Convert to all other formats
  let openai_chat_id = anthropic_to_openai_chat_call_id(anthropic_id)
  let openai_responses_id = anthropic_to_openai_responses_call_id(anthropic_id)
  let gemini_id = anthropic_to_gemini_id(anthropic_id)
  // All should be considered the same tool call
  assert_true(is_same_tool_call_id(anthropic_id, openai_chat_id))
  assert_true(is_same_tool_call_id(anthropic_id, openai_responses_id))
  assert_true(is_same_tool_call_id(anthropic_id, gemini_id))
  assert_true(is_same_tool_call_id(openai_chat_id, openai_responses_id))
  assert_true(is_same_tool_call_id(openai_chat_id, gemini_id))
  assert_true(is_same_tool_call_id(openai_responses_id, gemini_id))
}

// =============================================================================
// Message Conversion Round-trip Tests
// =============================================================================

///|
test "message roundtrip: OpenAI Chat -> Anthropic -> OpenAI Chat" {
  let original_messages = [
    @types.ModelMessage::User(content="Get weather in Tokyo", name=None),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(
          id="call_abc123",
          name="get_weather",
          arguments={ "location": "Tokyo" },
        ),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_abc123",
      content="{\"temp\": 25}",
    ),
  ]
  // Convert to Anthropic format
  let anthropic_messages = convert_message_tool_call_ids(
    original_messages,
    ToolCallIdProvider::AnthropicClaude,
  )
  // Verify Anthropic IDs
  match anthropic_messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
      assert_true(calls[0].id.has_prefix("toolu_"))
    _ => fail("Expected Assistant with tool_calls")
  }
  match anthropic_messages[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, ..) =>
      assert_true(tool_call_id.has_prefix("toolu_"))
    _ => fail("Expected ToolResult")
  }
  // Convert back to OpenAI Chat format
  let back_to_openai = convert_message_tool_call_ids(
    anthropic_messages,
    ToolCallIdProvider::OpenAIChatCompletions,
  )
  // Verify OpenAI Chat IDs
  match back_to_openai[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
      assert_true(calls[0].id.has_prefix("call_"))
    _ => fail("Expected Assistant with tool_calls")
  }
  match back_to_openai[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, ..) =>
      assert_true(tool_call_id.has_prefix("call_"))
    _ => fail("Expected ToolResult")
  }
  // Verify suffix is preserved
  match (original_messages[1], back_to_openai[1]) {
    (
      @types.ModelMessage::Assistant(tool_calls=Some(orig), ..),
      @types.ModelMessage::Assistant(tool_calls=Some(back), ..),
    ) => assert_true(is_same_tool_call_id(orig[0].id, back[0].id))
    _ => fail("Expected matching Assistant messages")
  }
}

///|
test "message conversion: multiple tool calls maintain order and mapping" {
  let messages = [
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="call_first", name="tool_a", arguments={}),
        @types.ToolCallRequest::new(id="call_second", name="tool_b", arguments={}),
        @types.ToolCallRequest::new(id="call_third", name="tool_c", arguments={}),
      ]),
    ),
    @types.ModelMessage::ToolResult(tool_call_id="call_first", content="result_a"),
    @types.ModelMessage::ToolResult(tool_call_id="call_second", content="result_b"),
    @types.ModelMessage::ToolResult(tool_call_id="call_third", content="result_c"),
  ]
  // Convert to Anthropic
  let converted = convert_message_tool_call_ids(
    messages,
    ToolCallIdProvider::AnthropicClaude,
  )
  // Verify order is preserved
  match converted[0] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      inspect(calls.length(), content="3")
      inspect(calls[0].name, content="tool_a")
      inspect(calls[1].name, content="tool_b")
      inspect(calls[2].name, content="tool_c")
      // All should have toolu_ prefix
      assert_true(calls[0].id.has_prefix("toolu_"))
      assert_true(calls[1].id.has_prefix("toolu_"))
      assert_true(calls[2].id.has_prefix("toolu_"))
    }
    _ => fail("Expected Assistant with tool_calls")
  }
  // Verify tool results maintain correct mapping
  match converted[1] {
    @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
      assert_true(tool_call_id.has_prefix("toolu_"))
      inspect(content, content="result_a")
      // Should match first tool call
      match converted[0] {
        @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
          assert_true(is_same_tool_call_id(tool_call_id, calls[0].id))
        _ => fail("Expected Assistant")
      }
    }
    _ => fail("Expected ToolResult")
  }
}

// =============================================================================
// Edge Cases
// =============================================================================

///|
test "edge case: empty suffix ID" {
  let id_with_empty_suffix = "call_"
  let converted = openai_chat_to_anthropic_tool_use_id(id_with_empty_suffix)
  inspect(converted, content="toolu_")
}

///|
test "edge case: ID with multiple underscores" {
  let id_with_underscores = "call_part1_part2_part3"
  let converted = openai_chat_to_anthropic_tool_use_id(id_with_underscores)
  // Should preserve everything after first underscore
  inspect(converted, content="toolu_part1_part2_part3")
}

///|
test "edge case: ID with no underscore" {
  let id_no_underscore = "abc123"
  let converted = convert_tool_call_id_to(
    id_no_underscore,
    ToolCallIdProvider::AnthropicClaude,
  )
  // Entire ID becomes suffix
  inspect(converted, content="toolu_abc123")
}

///|
test "edge case: very long ID" {
  let long_id = "call_" + "a".repeat(100)
  let converted = openai_chat_to_anthropic_tool_use_id(long_id)
  assert_true(converted.has_prefix("toolu_"))
  // Length should be prefix + original suffix
  inspect(converted.iter().count(), content="106") // "toolu_" (6) + "a" * 100
}

// =============================================================================
// Provider Format Specification Tests
// =============================================================================

///|
test "ToolCallIdFormat: all providers have correct specifications" {
  // OpenAI Chat Completions
  let openai_chat = ToolCallIdProvider::OpenAIChatCompletions.format()
  inspect(openai_chat.prefix, content="call_")
  inspect(openai_chat.has_native_id, content="true")
  // OpenAI Responses API
  let openai_responses = ToolCallIdProvider::OpenAIResponsesApi.format()
  inspect(openai_responses.prefix, content="fc_")
  inspect(openai_responses.has_native_id, content="true")
  // Anthropic Claude
  let anthropic = ToolCallIdProvider::AnthropicClaude.format()
  inspect(anthropic.prefix, content="toolu_")
  inspect(anthropic.has_native_id, content="true")
  // Google Gemini
  let gemini = ToolCallIdProvider::GoogleGemini.format()
  inspect(gemini.prefix, content="gemini_")
  inspect(gemini.has_native_id, content="false")
  // Unknown
  let unknown = ToolCallIdProvider::Unknown.format()
  inspect(unknown.prefix, content="")
  inspect(unknown.has_native_id, content="false")
}

// =============================================================================
// Generated ID Uniqueness Tests
// =============================================================================

///|
test "generated IDs: sequential calls produce unique IDs" {
  reset_tool_call_id_counter()
  let id1 = generate_openai_chat_call_id()
  let id2 = generate_openai_chat_call_id()
  let id3 = generate_anthropic_tool_use_id()
  let id4 = generate_openai_responses_call_id()
  // All should be different
  assert_true(id1 != id2)
  assert_true(id2 != id3)
  assert_true(id3 != id4)
  // But suffixes (counter values) should be sequential
  inspect(id1, content="call_1")
  inspect(id2, content="call_2")
  inspect(id3, content="toolu_3")
  inspect(id4, content="fc_4")
}

///|
test "generate_gemini_tool_call_id: format includes tool name and index" {
  let id1 = generate_gemini_tool_call_id("get_weather", 0)
  let id2 = generate_gemini_tool_call_id("search", 1)
  let id3 = generate_gemini_tool_call_id("get_weather", 1)
  inspect(id1, content="gemini_get_weather_0")
  inspect(id2, content="gemini_search_1")
  inspect(id3, content="gemini_get_weather_1")
  // Different tools with same index are different
  assert_true(id1 != id2)
  // Same tool with different index are different
  assert_true(id1 != id3)
}
