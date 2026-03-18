///|
/// SSE package tests

// =============================================================================
// Parser Tests
// =============================================================================

///|
test "parse_jsonl handles basic stream" {
  let jsonl =
    #| {"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
    #| {"choices":[{"delta":{},"finish_reason":"stop"}]}
    #| [DONE]
  let events = parse_jsonl(jsonl)
  inspect(events.length(), content="3")
  inspect(events[0].event, content="")
}

///|
test "parse_jsonl handles event+data format" {
  let jsonl =
    #| {"event":"message_start","data":{"type":"message_start"}}
    #| {"event":"content_block_delta","data":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}
    #| {"event":"message_stop","data":{"type":"message_stop"}}
  let events = parse_jsonl(jsonl)
  inspect(events.length(), content="3")
  inspect(events[0].event, content="message_start")
  inspect(events[1].event, content="content_block_delta")
}
