///|
/// SSE package tests

///|
fn read_sse_fixture(path : String) -> String raise {
  @fs.read_file_to_string(path)
}

// =============================================================================
// Parser Tests
// =============================================================================

///|
test "parse_chat_completions_jsonl handles basic stream" {
  let jsonl =
    #| {"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
    #| {"choices":[{"delta":{},"finish_reason":"stop"}]}
    #| [DONE]
  let events = parse_chat_completions_jsonl(jsonl)
  inspect(events.length(), content="3")
  inspect(events[0].event, content="")
}

///|
test "parse_event_stream_jsonl handles event+data format" {
  let jsonl =
    #| {"event":"message_start","data":{"type":"message_start"}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}
    #| {"event":"message_stop","data":{"type":"message_stop"}}
  let events = parse_event_stream_jsonl(jsonl)
  inspect(events.length(), content="3")
  inspect(events[0].event, content="message_start")
  inspect(events[1].event, content="content_block_delta")
}

// =============================================================================
// Chat Completions Accumulator Tests
// =============================================================================

///|
test "ChatCompletionsAccumulator accumulates text" {
  let acc = ChatCompletionsAccumulator::new()
  let event1 : SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  let event2 : SseEvent = {
    event: "",
    data: {
      "choices": Json::array([{ "index": 0, "delta": { "content": "Hello, " } }]),
    },
  }
  let event3 : SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "content": "world!" },
          "finish_reason": "stop",
        },
      ]),
    },
  }
  acc.feed(event1)
  acc.feed(event2)
  acc.feed(event3)
  let result = acc.finish()
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello, world!")
    _ => fail("Expected Text response")
  }
}

///|
test "ChatCompletionsAccumulator handles tool calls" {
  let jsonl =
    #| {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"tool_calls":[{"id":"fc_123","type":"function","function":{"name":"datetime","arguments":"{}"}}]},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
  let result = accumulate_chat_completions(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected ToolCalls response")
  }
}

// =============================================================================
// Harmony Accumulator Tests
// =============================================================================

///|
test "HarmonyAccumulator captures reasoning" {
  let acc = HarmonyAccumulator::new()
  let event1 : SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "reasoning": "Let me think...", "channel": "analysis" },
        },
      ]),
    },
  }
  let event2 : SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "content": "The answer is 42", "channel": "final" },
          "finish_reason": "stop",
        },
      ]),
    },
  }
  acc.feed(event1)
  acc.feed(event2)
  let result = acc.finish()
  let reasoning = acc.get_reasoning()
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="The answer is 42")
    _ => fail("Expected Text response")
  }
  inspect(reasoning, content="Let me think...")
}

///|
test "accumulate_harmony handles tool calls" {
  let jsonl =
    #| {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"tool_calls":[{"id":"fc_123","type":"function","function":{"name":"datetime","arguments":"{}"}}]},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
  let result = accumulate_harmony(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="fc_123")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "accumulate_harmony fixture multi tool stream keeps arguments by index" {
  let jsonl = read_sse_fixture(
    "testdata/sse_fixtures/groq/harmony/multi_toolcall_stream.jsonl",
  ) catch {
    err => {
      fail("Failed to read fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_harmony(jsonl) catch {
    err => {
      fail("Failed to accumulate harmony fixture: " + err.to_string())
      return
    }
  }
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].id, "fc_search")
      assert_eq(calls[0].name, "search")
      inspect(
        calls[0].arguments.stringify(),
        content="{\"q\":\"Tokyo weather\"}",
      )
      assert_eq(calls[1].id, "fc_calc")
      assert_eq(calls[1].name, "calculate")
      inspect(
        calls[1].arguments.stringify(),
        content="{\"expression\":\"2+2\"}",
      )
    }
    _ => fail("Expected ToolCalls response")
  }
}

// =============================================================================
// Responses API Accumulator Tests
// =============================================================================

///|
test "ResponsesApiAccumulator text stream" {
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"Hello","sequence_number":1}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":" World","sequence_number":2}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":3}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello World")
    _ => fail("Expected Text response")
  }
}

///|
test "ResponsesApiAccumulator tool call stream" {
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_item.added","data":{"type":"response.output_item.added","item":{"type":"function_call","call_id":"fc_001","name":"get_weather"},"sequence_number":1}}
    #| {"event":"response.function_call_arguments.delta","data":{"type":"response.function_call_arguments.delta","delta":"{\"city\":\"Tokyo\"}","sequence_number":2}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":3}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      inspect(calls[0].id, content="fc_001")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "ResponsesApiAccumulator fixture multi tool stream routes deltas by output_index" {
  let jsonl = read_sse_fixture(
    "testdata/sse_fixtures/openai/responses/multi_toolcall_stream.jsonl",
  ) catch {
    err => {
      fail("Failed to read fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_responses_api(jsonl) catch {
    err => {
      fail("Failed to accumulate responses fixture: " + err.to_string())
      return
    }
  }
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].id, "fc_search")
      assert_eq(calls[0].name, "search")
      inspect(
        calls[0].arguments.stringify(),
        content="{\"q\":\"Tokyo weather\"}",
      )
      assert_eq(calls[1].id, "fc_calc")
      assert_eq(calls[1].name, "calculate")
      inspect(
        calls[1].arguments.stringify(),
        content="{\"expression\":\"2+2\"}",
      )
    }
    _ => fail("Expected ToolCalls response")
  }
}

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
  let result = accumulate_anthropic_messages(jsonl)
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
  let result = accumulate_anthropic_messages(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="toolu_123")
      inspect(calls[0].name, content="search")
    }
    _ => fail("Expected ToolCalls response")
  }
}
