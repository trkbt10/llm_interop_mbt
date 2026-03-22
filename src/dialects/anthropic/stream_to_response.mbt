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
