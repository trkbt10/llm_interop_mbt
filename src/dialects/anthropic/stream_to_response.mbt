///|
/// SSE stream to ModelResponse conversion for Anthropic

///|
/// Process Anthropic Messages JSONL and return ModelResponse
pub fn accumulate_messages(content : String) -> @types.ModelResponse raise {
  let events = @sse.parse_jsonl(content)
  let acc = AnthropicMessagesAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Convert a non-streaming Anthropic Messages response into synthetic SSE events
/// that AnthropicToResponsesTranslator can process.
pub fn non_streaming_to_synthetic_events(json : Json) -> Array[@sse.SseEvent] {
  let events : Array[@sse.SseEvent] = []
  events.push({
    event: "message_start",
    data: { "type": "message_start", "message": json },
  })
  match json {
    { "content": Array(blocks), .. } =>
      for i, block in blocks {
        events.push({
          event: "content_block_start",
          data: {
            "type": "content_block_start",
            "index": i,
            "content_block": block,
          },
        })
        // Ref: docs/upstream/anthropic-messages-api.md:3958-3981 — response content block types
        match block {
          { "type": String("text"), "text": String(text), .. } =>
            events.push({
              event: "content_block_delta",
              data: {
                "type": "content_block_delta",
                "index": i,
                "delta": { "type": "text_delta", "text": text },
              },
            })
          { "type": String("tool_use"), "input": input, .. } =>
            events.push({
              event: "content_block_delta",
              data: {
                "type": "content_block_delta",
                "index": i,
                "delta": {
                  "type": "input_json_delta",
                  "partial_json": input.stringify(),
                },
              },
            })
          // Ref: docs/upstream/anthropic-messages-api.md:3971-3979 — ThinkingBlock
          { "type": String("thinking"), "thinking": String(thinking_text), .. } =>
            events.push({
              event: "content_block_delta",
              data: {
                "type": "content_block_delta",
                "index": i,
                "delta": { "type": "thinking_delta", "thinking": thinking_text },
              },
            })
          // Ref: docs/upstream/anthropic-messages-api.md:3981 — RedactedThinkingBlock
          { "type": String("redacted_thinking"), "data": String(data), .. } =>
            events.push({
              event: "content_block_delta",
              data: {
                "type": "content_block_delta",
                "index": i,
                "delta": { "type": "redacted_thinking_delta", "data": data },
              },
            })
          // Ref: docs/upstream/anthropic-code-execution-tool.md:1796-1802
          //   {"type":"bash_code_execution_tool_result","content":{"stdout":"...","stderr":"","return_code":0}}
          {
            "type": String("code_execution_tool_result"),
            "content": content_obj,
            ..
          } =>
            events.push({
              event: "content_block_delta",
              data: {
                "type": "content_block_delta",
                "index": i,
                "delta": {
                  "type": "code_execution_result_delta",
                  "content": content_obj,
                },
              },
            })
          _ => ()
        }
        events.push({
          event: "content_block_stop",
          data: { "type": "content_block_stop", "index": i },
        })
      }
    _ => ()
  }
  events.push({ event: "message_stop", data: { "type": "message_stop" } })
  events
}
