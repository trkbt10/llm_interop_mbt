///|
/// Content converter tests
/// Ported from llm-interop TypeScript: adapters/claude-to-openai/input-converters/

// =============================================================================
// Image Conversion Tests
// =============================================================================

///|
test "image: converts base64 image to Responses API format" {
  let image : Json = {
    "type": "image",
    "source": {
      "type": "base64",
      "data": "aGVsbG8gd29ybGQ=",
      "media_type": "image/jpeg",
    },
  }
  let result = convert_claude_image_to_responses(image)
  match result {
    {
      "type": String("input_image"),
      "image_url": String(url),
      "detail": String("auto"),
      ..
    } => assert_eq(url, "data:image/jpeg;base64,aGVsbG8gd29ybGQ=")
    _ => fail("Expected input_image format")
  }
}

///|
test "image: converts URL image to Responses API format" {
  let image : Json = {
    "type": "image",
    "source": { "type": "url", "url": "https://example.com/img.jpg" },
  }
  let result = convert_claude_image_to_responses(image)
  match result {
    { "type": String("input_image"), "image_url": String(url), .. } =>
      assert_eq(url, "https://example.com/img.jpg")
    _ => fail("Expected input_image format")
  }
}

///|
test "image: is_image_block detection" {
  assert_true(is_image_block({ "type": "image", "source": {} }))
  assert_false(is_image_block({ "type": "text", "text": "hello" }))
}

///|
test "image: invalid or non-image blocks fall back to empty URL" {
  match convert_claude_image_to_responses({ "type": "image", "source": {} }) {
    { "image_url": String(url), .. } => assert_eq(url, "")
    _ => fail("Expected empty input_image fallback")
  }

  match convert_claude_image_to_responses({ "type": "text", "text": "hello" }) {
    { "image_url": String(url), .. } => assert_eq(url, "")
    _ => fail("Expected non-image fallback")
  }
}

// =============================================================================
// Tool Result Conversion Tests
// =============================================================================

///|
test "tool_result: converts string content" {
  let block : Json = {
    "type": "tool_result",
    "tool_use_id": "toolu_01ABC123",
    "content": "Weather in Tokyo: 22°C",
  }
  let result = convert_claude_tool_result_to_responses(block)
  match result {
    {
      "type": String("function_call_output"),
      "id": String(id),
      "call_id": String(call_id),
      "output": String(output),
      ..
    } => {
      assert_true(id.has_prefix("fc_"))
      assert_true(call_id.has_prefix("call_"))
      assert_eq(output, "Weather in Tokyo: 22°C")
      // Verify ID suffix is preserved
      assert_true(@interop_util.is_same_tool_call_id("toolu_01ABC123", id))
      assert_true(@interop_util.is_same_tool_call_id("toolu_01ABC123", call_id))
    }
    _ => fail("Expected function_call_output format")
  }
}

///|
test "tool_result: converts complex content to JSON string" {
  let block : Json = {
    "type": "tool_result",
    "tool_use_id": "toolu_xyz789",
    "content": Json::array([{ "type": "text", "text": "{\"temperature\":22}" }]),
  }
  let result = convert_claude_tool_result_to_responses(block)
  match result {
    { "output": String(output), .. } =>
      // Should be stringified JSON
      assert_true(output.contains("temperature"))
    _ => fail("Expected output string")
  }
}

///|
test "tool_result: is_tool_result_block detection" {
  assert_true(
    is_tool_result_block({
      "type": "tool_result",
      "tool_use_id": "x",
      "content": "y",
    }),
  )
  assert_false(is_tool_result_block({ "type": "tool_use" }))
}

///|
test "tool_result: fallback shape is empty" {
  match convert_claude_tool_result_to_responses({ "type": "text" }) {
    {
      "type": String("function_call_output"),
      "call_id": String(call_id),
      "output": String(output),
      ..
    } => {
      assert_eq(call_id, "")
      assert_eq(output, "")
    }
    _ => fail("Expected empty function_call_output fallback")
  }
}

// =============================================================================
// Tool Use Conversion Tests
// =============================================================================

///|
test "tool_use: converts to function_call format" {
  let block : Json = {
    "type": "tool_use",
    "id": "toolu_01DEF456",
    "name": "get_weather",
    "input": { "location": "Tokyo" },
  }
  let result = convert_claude_tool_use_to_responses(block)
  match result {
    {
      "type": String("function_call"),
      "call_id": String(call_id),
      "name": String(name),
      "arguments": String(args),
      ..
    } => {
      assert_true(call_id.has_prefix("fc_"))
      assert_eq(name, "get_weather")
      assert_true(args.contains("Tokyo"))
    }
    _ => fail("Expected function_call format")
  }
}

///|
test "tool_use/text helpers fall back cleanly on unsupported blocks" {
  match convert_claude_tool_use_to_responses({ "type": "text" }) {
    {
      "type": String("function_call"),
      "name": String(name),
      "arguments": String(arguments),
      ..
    } => {
      assert_eq(name, "")
      assert_eq(arguments, "{}")
    }
    _ => fail("Expected empty function_call fallback")
  }

  assert_true(is_tool_use_block({ "type": "tool_use", "id": "x" }))
  assert_false(is_tool_use_block({ "type": "text" }))

  match convert_claude_text_to_responses({ "type": "tool_use" }) {
    { "type": String("output_text"), "text": String(text), .. } =>
      assert_eq(text, "")
    _ => fail("Expected empty output_text fallback")
  }

  assert_true(is_text_block({ "type": "text", "text": "hello" }))
  assert_false(is_text_block({ "type": "tool_use" }))
}

// =============================================================================
// Text Conversion Tests
// =============================================================================

///|
test "text: converts to output_text format" {
  let block : Json = { "type": "text", "text": "Hello, world!" }
  let result = convert_claude_text_to_responses(block)
  match result {
    { "type": String("output_text"), "text": String(text), .. } =>
      assert_eq(text, "Hello, world!")
    _ => fail("Expected output_text format")
  }
}

// =============================================================================
// Responses API -> Claude Conversion Tests
// =============================================================================

///|
test "function_call: converts to tool_use format" {
  let block : Json = {
    "type": "function_call",
    "call_id": "fc_01GHI789",
    "name": "calculate",
    "arguments": "{\"expression\": \"2+2\"}",
  }
  let result = convert_responses_function_call_to_claude(block)
  match result {
    {
      "type": String("tool_use"),
      "id": String(id),
      "name": String(name),
      "input": { "expression": String(expr), .. },
      ..
    } => {
      assert_true(id.has_prefix("toolu_"))
      assert_eq(name, "calculate")
      assert_eq(expr, "2+2")
    }
    _ => fail("Expected tool_use format")
  }
}

///|
test "web_search_call: converts to web_search tool_use format" {
  let block : Json = {
    "type": "web_search_call",
    "id": "ws_01GHI789",
    "action": { "type": "search", "query": "current weather in Tokyo" },
  }
  let result = convert_responses_function_call_to_claude(block)
  match result {
    {
      "type": String("tool_use"),
      "id": String(id),
      "name": String(name),
      "input": { "query": String(query), .. },
      ..
    } => {
      assert_true(id.has_prefix("toolu_"))
      assert_eq(name, "web_search")
      assert_eq(query, "current weather in Tokyo")
    }
    _ => fail("Expected tool_use format")
  }
}

///|
test "function_call/tool_result converters cover id and fallback branches" {
  let by_id = convert_responses_function_call_to_claude({
    "type": "function_call",
    "id": "fc_01XYZ",
    "name": "lookup",
    "arguments": "{}",
  })
  match by_id {
    { "type": String("tool_use"), "id": String(id), "name": String(name), .. } => {
      assert_true(id.has_prefix("toolu_"))
      assert_eq(name, "lookup")
    }
    _ => fail("Expected tool_use converted from id field")
  }

  let web_search_without_action = convert_responses_function_call_to_claude({
    "type": "web_search_call",
    "id": "ws_missing",
  })
  match web_search_without_action {
    {
      "type": String("tool_use"),
      "name": String(name),
      "input": Object(input),
      ..
    } => {
      assert_eq(name, "web_search")
      assert_eq(input.length(), 0)
    }
    _ => fail("Expected empty web_search input fallback")
  }

  match convert_responses_function_call_to_claude({ "type": "text" }) {
    {
      "type": String("tool_use"),
      "id": String(id),
      "name": String(name),
      "input": Object(input),
      ..
    } => {
      assert_eq(id, "")
      assert_eq(name, "")
      assert_eq(input.length(), 0)
    }
    _ => fail("Expected generic tool_use fallback")
  }

  match convert_responses_function_call_output_to_claude({ "type": "text" }) {
    {
      "type": String("tool_result"),
      "tool_use_id": String(tool_use_id),
      "content": String(content),
      ..
    } => {
      assert_eq(tool_use_id, "")
      assert_eq(content, "")
    }
    _ => fail("Expected generic tool_result fallback")
  }

  let generated_id = convert_responses_function_call_to_claude({
    "type": "function_call",
    "name": "lookup",
    "arguments": "{}",
  })
  match generated_id {
    { "type": String("tool_use"), "id": String(id), .. } =>
      assert_true(id.has_prefix("toolu_"))
    _ => fail("Expected generated anthropic tool_use id")
  }
}

///|
test "function_call_output: converts to tool_result format" {
  let block : Json = {
    "type": "function_call_output",
    "call_id": "fc_01JKL012",
    "output": "Result: 4",
  }
  let result = convert_responses_function_call_output_to_claude(block)
  match result {
    {
      "type": String("tool_result"),
      "tool_use_id": String(id),
      "content": String(content),
      ..
    } => {
      assert_true(id.has_prefix("toolu_"))
      assert_eq(content, "Result: 4")
    }
    _ => fail("Expected tool_result format")
  }
}

///|
test "input_image: converts URL to Claude format" {
  let block : Json = {
    "type": "input_image",
    "image_url": "https://example.com/photo.png",
  }
  let result = convert_responses_image_to_claude(block)
  match result {
    {
      "type": String("image"),
      "source": { "type": String("url"), "url": String(url), .. },
      ..
    } => assert_eq(url, "https://example.com/photo.png")
    _ => fail("Expected image with URL source")
  }
}

///|
test "input_image: converts data URI to Claude base64 format" {
  let block : Json = {
    "type": "input_image",
    "image_url": "data:image/png;base64,dGVzdA==",
  }
  let result = convert_responses_image_to_claude(block)
  match result {
    {
      "type": String("image"),
      "source": {
        "type": String("base64"),
        "media_type": String(media_type),
        "data": String(data),
        ..
      },
      ..
    } => {
      assert_eq(media_type, "image/png")
      assert_eq(data, "dGVzdA==")
    }
    _ => fail("Expected image with base64 source")
  }
}

///|
test "input_image: non-image blocks fall back to empty Claude URL" {
  match convert_responses_image_to_claude({ "type": "text" }) {
    {
      "type": String("image"),
      "source": { "type": String("url"), "url": String(url), .. },
      ..
    } => assert_eq(url, "")
    _ => fail("Expected empty Claude image fallback")
  }
}

// =============================================================================
// Roundtrip Tests
// =============================================================================

///|
test "roundtrip: tool_use -> function_call -> tool_use preserves data" {
  let original : Json = {
    "type": "tool_use",
    "id": "toolu_roundtrip_test",
    "name": "my_tool",
    "input": { "param": "value" },
  }
  let as_responses = convert_claude_tool_use_to_responses(original)
  let back_to_claude = convert_responses_function_call_to_claude(as_responses)
  match back_to_claude {
    { "name": String(name), "input": { "param": String(param), .. }, .. } => {
      assert_eq(name, "my_tool")
      assert_eq(param, "value")
    }
    _ => fail("Roundtrip failed")
  }
}

///|
test "roundtrip: image URL preserved through conversion" {
  let original : Json = {
    "type": "image",
    "source": { "type": "url", "url": "https://example.com/test.jpg" },
  }
  let as_responses = convert_claude_image_to_responses(original)
  let back_to_claude = convert_responses_image_to_claude(as_responses)
  match back_to_claude {
    { "source": { "url": String(url), .. }, .. } =>
      assert_eq(url, "https://example.com/test.jpg")
    _ => fail("Roundtrip failed")
  }
}
