///|
/// Anthropic dialect accumulator tests

// =============================================================================
// Anthropic Messages Accumulator Tests
// =============================================================================

///|
test "AnthropicMessagesAccumulator text stream" {
  let jsonl =
    #| {"event":"message_start","data":{"type":"message_start","message":{"id":"msg_1"}}}
    #| {"event":"content_block_start","data":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello Claude"}}}
    #| {"event":"content_block_stop","data":{"type":"content_block_stop","index":0}}
    #| {"event":"message_delta","data":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}
    #| {"event":"message_stop","data":{"type":"message_stop"}}
  let result = accumulate_messages(jsonl)
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello Claude")
    _ => fail("Expected Text response")
  }
}

///|
test "AnthropicMessagesAccumulator tool call stream" {
  let jsonl =
    #| {"event":"message_start","data":{"type":"message_start","message":{"id":"msg_1"}}}
    #| {"event":"content_block_start","data":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_123","name":"search","input":{}}}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"q\":\"test\"}"}}}
    #| {"event":"content_block_stop","data":{"type":"content_block_stop","index":0}}
    #| {"event":"message_delta","data":{"type":"message_delta","delta":{"stop_reason":"tool_use"}}}
    #| {"event":"message_stop","data":{"type":"message_stop"}}
  let result = accumulate_messages(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="toolu_123")
      inspect(calls[0].name, content="search")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "AnthropicMessagesAccumulator preserves mixed text and tool call stream" {
  let jsonl =
    #| {"event":"message_start","data":{"type":"message_start","message":{"id":"msg_1"}}}
    #| {"event":"content_block_start","data":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me check"}}}
    #| {"event":"content_block_stop","data":{"type":"content_block_stop","index":0}}
    #| {"event":"content_block_start","data":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"search","input":{}}}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q\":\"test\"}"}}}
    #| {"event":"content_block_stop","data":{"type":"content_block_stop","index":1}}
    #| {"event":"message_delta","data":{"type":"message_delta","delta":{"stop_reason":"tool_use"}}}
    #| {"event":"message_stop","data":{"type":"message_stop"}}
  let result = accumulate_messages(jsonl)
  match result {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "search")
      assert_eq(rich.content, "Let me check")
    }
    _ => fail("Expected ToolCallsWithContent response")
  }
}

///|
test "non_streaming_to_synthetic_events preserves thinking block" {
  // Anthropic response with thinking + text
  let response : Json = {
    "content": Json::array([
      { "type": "thinking", "thinking": "Let me reason..." },
      { "type": "text", "text": "The answer is 42." },
    ]),
    "stop_reason": "end_turn",
    "model": "claude-sonnet-4-20250514",
  }
  let events = non_streaming_to_synthetic_events(response)
  // Verify thinking block generates a thinking_delta synthetic event
  let mut has_thinking_delta = false
  for event in events {
    match event.data {
      {
        "delta": { "type": String("thinking_delta"), "thinking": String(t), .. },
        ..
      } => {
        inspect(t, content="Let me reason...")
        has_thinking_delta = true
      }
      _ => ()
    }
  }
  assert_true(has_thinking_delta)
}

///|
test "non_streaming_to_synthetic_events preserves code_execution_tool_result" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "toolu_456",
        "content": { "stdout": "42", "stderr": "", "return_code": 0 },
      },
      { "type": "text", "text": "Done." },
    ]),
    "stop_reason": "end_turn",
    "model": "claude-sonnet-4-20250514",
  }
  let events = non_streaming_to_synthetic_events(response)
  let mut has_code_result = false
  for event in events {
    match event.data {
      { "delta": { "type": String("code_execution_result_delta"), .. }, .. } =>
        has_code_result = true
      _ => ()
    }
  }
  assert_true(has_code_result)
}

///|
test "AnthropicToResponsesTranslator coalesces thinking deltas into one reasoning item" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_thinking",
  )
  let start_event : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "type": "content_block_start",
      "index": 0,
      "content_block": { "type": "thinking", "thinking": "" },
    },
  }
  let delta1 : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "type": "content_block_delta",
      "index": 0,
      "delta": { "type": "thinking_delta", "thinking": "Let me " },
    },
  }
  let delta2 : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "type": "content_block_delta",
      "index": 0,
      "delta": { "type": "thinking_delta", "thinking": "reason this through." },
    },
  }
  let stop_event : @sse.SseEvent = {
    event: "content_block_stop",
    data: { "type": "content_block_stop", "index": 0 },
  }
  let start_events = translator.translate(start_event)
  let delta_events1 = translator.translate(delta1)
  let delta_events2 = translator.translate(delta2)
  let stop_events = translator.translate(stop_event)
  let mut delta1_has_done = false
  for pair in delta_events1 {
    if pair.0 == "response.output_item.done" {
      delta1_has_done = true
    }
  }
  let mut delta2_has_done = false
  for pair in delta_events2 {
    if pair.0 == "response.output_item.done" {
      delta2_has_done = true
    }
  }
  assert_eq(start_events.length(), 1)
  assert_eq(start_events[0].0, "response.created")
  assert_true(not(delta1_has_done))
  assert_true(not(delta2_has_done))
  assert_eq(stop_events.length(), 1)
  assert_eq(stop_events[0].0, "response.output_item.done")
  match stop_events[0].1 {
    {
      "item": { "type": String("reasoning"), "summary": Array(summary), .. },
      ..
    } =>
      match summary[0] {
        { "type": String("summary_text"), "text": String(text), .. } =>
          assert_eq(text, "Let me reason this through.")
        _ => fail("Expected summary_text block")
      }
    _ => fail("Expected reasoning output item")
  }
}

///|
test "AnthropicToResponsesTranslator emits web_search_call for server_tool_use" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_web_search",
  )
  let start_event : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "type": "content_block_start",
      "index": 0,
      "content_block": {
        "type": "server_tool_use",
        "id": "srvtoolu_01SEARCH",
        "name": "web_search",
      },
    },
  }
  let delta_event : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "type": "content_block_delta",
      "index": 0,
      "delta": {
        "type": "input_json_delta",
        "partial_json": "{\"query\":\"MoonBit\"}",
      },
    },
  }
  let stop_event : @sse.SseEvent = {
    event: "content_block_stop",
    data: { "type": "content_block_stop", "index": 0 },
  }
  let start_events = translator.translate(start_event)
  let _ = translator.translate(delta_event)
  let stop_events = translator.translate(stop_event)
  assert_eq(start_events[1].0, "response.output_item.added")
  match start_events[1].1 {
    { "item": { "type": String("web_search_call"), .. }, .. } => ()
    _ => fail("Expected web_search_call output item")
  }
  assert_eq(stop_events[1].0, "response.output_item.done")
  match stop_events[1].1 {
    {
      "item": {
        "type": String("web_search_call"),
        "action": { "query": String(query), .. },
        ..
      },
      ..
    } => assert_eq(query, "MoonBit")
    _ => fail("Expected completed web_search_call item")
  }
}

///|
test "AnthropicToResponsesTranslator emits encrypted reasoning for redacted thinking" {
  let translator = AnthropicToResponsesTranslator::new(
    response_id="resp_redacted",
  )
  let start_event : @sse.SseEvent = {
    event: "content_block_start",
    data: {
      "type": "content_block_start",
      "index": 0,
      "content_block": { "type": "redacted_thinking", "data": "" },
    },
  }
  let delta_event : @sse.SseEvent = {
    event: "content_block_delta",
    data: {
      "type": "content_block_delta",
      "index": 0,
      "delta": { "type": "redacted_thinking_delta", "data": "enc_blob" },
    },
  }
  let stop_event : @sse.SseEvent = {
    event: "content_block_stop",
    data: { "type": "content_block_stop", "index": 0 },
  }
  let _ = translator.translate(start_event)
  let _ = translator.translate(delta_event)
  let stop_events = translator.translate(stop_event)
  assert_eq(stop_events.length(), 1)
  match stop_events[0].1 {
    {
      "item": {
        "type": String("reasoning"),
        "encrypted_content": String(data),
        ..
      },
      ..
    } => assert_eq(data, "enc_blob")
    _ => fail("Expected encrypted reasoning item")
  }
}
