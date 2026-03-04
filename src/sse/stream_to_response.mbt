///|
/// SSE stream to ModelResponse conversion

///|
/// Process Chat Completions JSONL and return ModelResponse
pub fn accumulate_chat_completions(
  content : String,
) -> @types.ModelResponse raise {
  let events = parse_chat_completions_jsonl(content)
  let acc = ChatCompletionsAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Process Responses API JSONL and return ModelResponse
pub fn accumulate_responses_api(content : String) -> @types.ModelResponse raise {
  let events = parse_event_stream_jsonl(content)
  let acc = ResponsesApiAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Process Anthropic Messages JSONL and return ModelResponse
pub fn accumulate_anthropic_messages(
  content : String,
) -> @types.ModelResponse raise {
  let events = parse_event_stream_jsonl(content)
  let acc = AnthropicMessagesAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

///|
/// Process Harmony Chat Completions JSONL and return ModelResponse
pub fn accumulate_harmony(content : String) -> @types.ModelResponse raise {
  let events = parse_chat_completions_jsonl(content)
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
  let events = parse_chat_completions_jsonl(content)
  let acc = HarmonyAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  (acc.finish(), acc.get_reasoning())
}
