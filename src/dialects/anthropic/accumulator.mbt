///|
/// Anthropic Messages API stream accumulator

///|
/// Anthropic Messages API stream accumulator
/// Accumulates content_block_delta (text_delta / input_json_delta)
pub struct AnthropicMessagesAccumulator {
  text : StringBuilder
  tool_calls : Array[@types.ToolCallAcc]
  mut stop_reason : String
}

///|
/// Creates a new empty accumulator
pub fn AnthropicMessagesAccumulator::new() -> AnthropicMessagesAccumulator {
  { text: StringBuilder::new(), tool_calls: [], stop_reason: "" }
}

///|
/// Process SSE event
pub fn AnthropicMessagesAccumulator::feed(
  self : AnthropicMessagesAccumulator,
  event : @sse.SseEvent,
) -> Unit {
  match event.event {
    "content_block_start" =>
      match event.data {
        {
          "content_block": {
            "type": String("tool_use"),
            "id": String(id),
            "name": String(name),
            ..
          },
          ..
        } =>
          self.tool_calls.push(@types.ToolCallAcc::{
            id,
            name,
            arguments: StringBuilder::new(),
          })
        _ => ()
      }
    "content_block_delta" =>
      match event.data {
        { "delta": { "type": String("text_delta"), "text": String(t), .. }, .. } =>
          self.text.write_string(t)
        {
          "delta": {
            "type": String("input_json_delta"),
            "partial_json": String(pj),
            ..
          },
          ..
        } =>
          if self.tool_calls.length() > 0 {
            self.tool_calls[self.tool_calls.length() - 1].arguments.write_string(
              pj,
            )
          }
        _ => ()
      }
    "message_delta" =>
      match event.data {
        { "delta": { "stop_reason": String(sr), .. }, .. } =>
          self.stop_reason = sr
        _ => ()
      }
    _ => () // message_start, content_block_stop, ping, message_stop
  }
}

///|
/// Get final result
pub fn AnthropicMessagesAccumulator::finish(
  self : AnthropicMessagesAccumulator,
) -> @types.ModelResponse {
  if self.stop_reason == "tool_use" && self.tool_calls.length() > 0 {
    @types.ModelResponse::ToolCalls(
      @types.tool_calls_to_requests(self.tool_calls),
    )
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}
