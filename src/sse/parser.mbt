///|
/// SSE parser for complete (non-chunked) JSONL content

///|
/// Parse JSONL content into SSE events.
/// Each line is parsed as JSON. If the JSON has "event" and "data" fields,
/// they are extracted; otherwise the entire JSON becomes the data with event="".
/// Blank lines and [DONE] markers are skipped.
pub fn parse_jsonl(content : String) -> Array[SseEvent] raise {
  let events : Array[SseEvent] = []
  for line in @utils.split_lines(content) {
    let trimmed = line.trim().to_string()
    if trimmed.length() == 0 || trimmed == "[DONE]" {
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
