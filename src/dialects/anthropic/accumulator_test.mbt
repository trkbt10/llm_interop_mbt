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
