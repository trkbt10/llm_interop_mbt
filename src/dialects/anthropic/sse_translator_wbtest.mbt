///|
/// Whitebox coverage for Anthropic SSE translator branches

///|
test "translator handles function tool use, argument deltas, and completion" {
  let translator = AnthropicToResponsesTranslator::new(response_id="resp_fn")
  let start_event : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "content_block": {
        "type": "tool_use",
        "id": "toolu_123",
        "name": "lookup",
      },
    },
  }
  let delta_event : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "input_json_delta",
        "partial_json": "{\"q\":\"moonbit\"}",
      },
    },
  }
  let stop_event : @sse.SseEvent = { event: "content_block_stop", data: {} }

  let start_events = translator.translate(start_event)
  assert_eq(start_events.length(), 2)
  assert_eq(start_events[0].0, "response.created")
  assert_eq(start_events[1].0, "response.output_item.added")

  let delta_events = translator.translate(delta_event)
  assert_eq(delta_events.length(), 1)
  assert_eq(delta_events[0].0, "response.function_call_arguments.delta")
  assert_true(translator.current_tool_call_id.length() > 0)

  let stop_events = translator.translate(stop_event)
  assert_eq(stop_events.length(), 1)
  assert_eq(stop_events[0].0, "response.output_item.done")
  assert_eq(translator.current_tool_call_id, "")
  assert_eq(translator.current_tool_mode, "")
}

///|
test "translator handles text deltas, code execution output, and stop notifications" {
  let translator = AnthropicToResponsesTranslator::new(response_id="resp_text")
  let text_delta : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "text_delta", "text": "Hello" } },
  }
  let code_delta : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "code_execution_result_delta",
        "content": { "stdout": "42", "stderr": "warn" },
      },
    },
  }
  let message_delta : @sse.SseEvent = {
    event: "message_delta",
    data: { "delta": { "stop_reason": "pause_turn" } },
  }
  let message_stop : @sse.SseEvent = { event: "message_stop", data: {} }

  let text_events = translator.translate(text_delta)
  assert_eq(text_events.length(), 2)
  assert_eq(text_events[0].0, "response.created")
  assert_eq(text_events[1].0, "response.output_text.delta")

  let code_events = translator.translate(code_delta)
  assert_eq(code_events.length(), 1)
  assert_eq(code_events[0].0, "response.output_text.delta")
  assert_true(translator.get_text().contains("Hello"))
  assert_true(translator.get_text().contains("Code execution output"))
  assert_true(translator.get_text().contains("[stderr]"))

  let done_events = translator.translate(message_delta)
  assert_eq(done_events.length(), 1)
  assert_eq(done_events[0].0, "response.output_text.done")
  match done_events[0].1 {
    { "text": String(text), .. } => {
      assert_true(text.contains("Hello"))
      assert_true(text.contains("42"))
    }
    _ => fail("Expected output_text.done payload")
  }

  let completed_events = translator.translate(message_stop)
  assert_eq(completed_events.length(), 1)
  assert_eq(completed_events[0].0, "response.completed")
}

///|
test "translator preserves structured JSON text deltas exactly" {
  let translator = AnthropicToResponsesTranslator::new(response_id="resp_json")
  let first : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "text_delta", "text": "{\"answer\":" } },
  }
  let second : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "text_delta",
        "text": "{\"url\":\"https://example.com\"}}",
      },
    },
  }
  let done : @sse.SseEvent = {
    event: "message_delta",
    data: { "delta": { "stop_reason": "end_turn" } },
  }
  let first_events = translator.translate(first)
  let second_events = translator.translate(second)
  let done_events = translator.translate(done)
  assert_eq(first_events[1].0, "response.output_text.delta")
  assert_eq(second_events[0].0, "response.output_text.delta")
  match done_events[0].1 {
    { "text": String(text), .. } =>
      assert_eq(text, "{\"answer\":{\"url\":\"https://example.com\"}}")
    _ => fail("Expected output_text.done payload")
  }
}

///|
test "translator preserves invalid structured JSON text without validation" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_invalid_json",
  )
  let first : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "text_delta", "text": "{\"answer\":" } },
  }
  let second : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "text_delta", "text": "oops}" } },
  }
  let done : @sse.SseEvent = {
    event: "message_delta",
    data: { "delta": { "stop_reason": "end_turn" } },
  }
  ignore(translator.translate(first))
  ignore(translator.translate(second))
  let done_events = translator.translate(done)
  match done_events[0].1 {
    { "text": String(text), .. } => assert_eq(text, "{\"answer\":oops}")
    _ => fail("Expected output_text.done payload")
  }
}

///|
test "translator handles non-web server tools and ignored events" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_server",
  )
  let start_event : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "content_block": {
        "type": "server_tool_use",
        "id": "srvtoolu_code",
        "name": "code_execution",
      },
    },
  }
  let delta_event : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "input_json_delta",
        "partial_json": "{\"code\":\"print(1)\"}",
      },
    },
  }
  let stop_event : @sse.SseEvent = { event: "content_block_stop", data: {} }
  let ping_event : @sse.SseEvent = { event: "ping", data: {} }

  let start_events = translator.translate(start_event)
  assert_eq(start_events.length(), 1)
  assert_eq(start_events[0].0, "response.created")
  assert_eq(translator.current_tool_mode, "server_tool")

  let delta_events = translator.translate(delta_event)
  assert_eq(delta_events.length(), 0)

  let stop_events = translator.translate(stop_event)
  assert_eq(stop_events.length(), 0)
  assert_eq(translator.current_tool_call_id, "")
  assert_eq(translator.current_tool_mode, "")

  let ping_events = translator.translate(ping_event)
  assert_eq(ping_events.length(), 0)
}

///|
test "translator covers malformed deltas and web search fallback parsing" {
  let code_translator = AnthropicToResponsesTranslator::new(
    response_id="resp_code",
  )
  let stderr_only : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "code_execution_result_delta",
        "content": { "stderr": "only stderr" },
      },
    },
  }
  let empty_result : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "code_execution_result_delta", "content": {} } },
  }
  let unknown_delta : @sse.SseEvent = {
    event: "content_block_delta",
    data: { "delta": { "type": "unknown_delta" } },
  }
  let invalid_message_delta : @sse.SseEvent = {
    event: "message_delta",
    data: { "delta": { "other": true } },
  }

  let stderr_events = code_translator.translate(stderr_only)
  match stderr_events[1].1 {
    { "delta": String(text), .. } =>
      assert_eq(text, "Code execution [stderr]:\nonly stderr")
    _ => fail("Expected stderr-only output")
  }
  let empty_events = code_translator.translate(empty_result)
  match empty_events[0].1 {
    { "delta": String(text), .. } =>
      assert_eq(text, "Code execution completed (no output)")
    _ => fail("Expected empty code execution fallback")
  }
  assert_eq(code_translator.translate(unknown_delta).length(), 0)
  assert_eq(code_translator.translate(invalid_message_delta).length(), 0)

  let web_translator = AnthropicToResponsesTranslator::new(
    response_id="resp_web_bad",
  )
  let web_start : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "content_block": {
        "type": "server_tool_use",
        "id": "srvtoolu_01SEARCH",
        "name": "web_search",
      },
    },
  }
  let web_delta : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": { "type": "input_json_delta", "partial_json": "{invalid" },
    },
  }
  let web_stop : @sse.SseEvent = { event: "content_block_stop", data: {} }
  let _ = web_translator.translate(web_start)
  let _ = web_translator.translate(web_delta)
  let web_stop_events = web_translator.translate(web_stop)
  match web_stop_events[1].1 {
    { "item": { "action": { "type": String("search"), .. }, .. }, .. } => ()
    _ => fail("Expected web_search fallback action")
  }
}

///|
test "translator formats stdout-only code execution results" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_stdout",
  )
  let event : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "delta": {
        "type": "code_execution_result_delta",
        "content": { "stdout": "print(42)" },
      },
    },
  }
  let translated = translator.translate(event)
  match translated[1].1 {
    { "delta": String(text), .. } =>
      assert_eq(text, "Code execution output:\nprint(42)")
    _ => fail("Expected stdout-only code execution output")
  }
}
