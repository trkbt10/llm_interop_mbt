///|
/// SSE parser functions

///|
/// Parse Chat Completions format JSONL
/// Format: Each line is JSON (no event: header). Ends with [DONE].
pub fn parse_chat_completions_jsonl(content : String) -> Array[SseEvent] raise {
  let events : Array[SseEvent] = []
  let lines = @utils.split_lines(content)
  for line in lines {
    let trimmed = line.trim().to_string()
    if trimmed.length() == 0 || trimmed == "[DONE]" {
      continue
    }
    let json = @json.parse(trimmed)
    events.push({ event: "", data: json })
  }
  events
}

///|
/// Parse Responses API / Anthropic Messages format JSONL
/// Format: Each line is {"event":"...","data":{...}}
pub fn parse_event_stream_jsonl(content : String) -> Array[SseEvent] raise {
  let events : Array[SseEvent] = []
  let lines = @utils.split_lines(content)
  for line in lines {
    let trimmed = line.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    let json = @json.parse(trimmed)
    match json {
      { "event": String(event), "data": data, .. } =>
        events.push({ event, data })
      _ => events.push({ event: "", data: json })
    }
  }
  events
}
