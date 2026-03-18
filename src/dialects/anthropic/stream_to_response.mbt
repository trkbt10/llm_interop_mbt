///|
/// SSE stream to ModelResponse conversion for Anthropic

///|
/// Process Anthropic Messages JSONL and return ModelResponse
pub fn accumulate_anthropic_messages(
  content : String,
) -> @types.ModelResponse raise {
  let events = @sse.parse_jsonl(content)
  let acc = AnthropicMessagesAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}
