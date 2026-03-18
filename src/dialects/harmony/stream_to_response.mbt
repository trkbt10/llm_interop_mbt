///|
/// SSE stream to ModelResponse conversion for Harmony

///|
/// Process Harmony Chat Completions JSONL and return ModelResponse
pub fn accumulate_harmony(content : String) -> @types.ModelResponse raise {
  let events = @sse.parse_jsonl(content)
  let acc = HarmonyAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Process Harmony Chat Completions JSONL and return result with reasoning
pub fn accumulate_harmony_with_reasoning(
  content : String,
) -> (@types.ModelResponse, String) raise {
  let events = @sse.parse_jsonl(content)
  let acc = HarmonyAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  (acc.finish(), acc.get_reasoning())
}
