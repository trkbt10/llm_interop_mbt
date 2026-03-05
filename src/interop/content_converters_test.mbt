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
      assert_true(is_same_tool_call_id("toolu_01ABC123", id))
      assert_true(is_same_tool_call_id("toolu_01ABC123", call_id))
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
