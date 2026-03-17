///|
/// SSE stream to ModelResponse conversion for OpenAI

///|
/// Process Chat Completions JSONL and return ModelResponse
pub fn accumulate_chat_completions(
  content : String,
) -> @types.ModelResponse raise {
  let events = @sse.parse_chat_completions_jsonl(content)
  let acc = ChatCompletionsAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Process Responses API JSONL and return ModelResponse
pub fn accumulate_responses_api(content : String) -> @types.ModelResponse raise {
  let events = @sse.parse_event_stream_jsonl(content)
  let acc = ResponsesApiAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}
