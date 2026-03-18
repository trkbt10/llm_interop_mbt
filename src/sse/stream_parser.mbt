///|
/// Chunk-based SSE stream parser
/// Handles incomplete lines across chunk boundaries

///|
/// Parsed events with remaining unparsed content
pub(all) struct ParsedChunk {
  events : Array[SseEvent]
  remaining : String
}

///|
/// Parse an SSE chunk, handling both "event: type\ndata: json" and
/// bare "data: json" formats. Incomplete trailing lines are returned
/// in `remaining` for the caller to prepend to the next chunk.
pub fn parse_sse_chunk(content : String) -> ParsedChunk {
  let events : Array[SseEvent] = []
  let lines = @utils.split_lines(content)
  let remaining = StringBuilder::new()
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let trimmed = line.trim().to_string()
    if i == lines.length() - 1 &&
      trimmed.length() > 0 &&
      not(content.has_suffix("\n")) {
      remaining.write_string(line)
      break
    }
    if trimmed.length() == 0 || trimmed == "[DONE]" {
      i = i + 1
      continue
    }
    if trimmed.has_prefix("event:") {
      let event_type = safe_substring(trimmed, 6)
      i = i + 1
      if i < lines.length() {
        let data_line = lines[i].trim().to_string()
        if data_line.has_prefix("data:") {
          let data_str = safe_substring(data_line, 5)
          if data_str != "[DONE]" {
            let data = @json.parse(data_str) catch { _ => Json::null() }
            events.push({ event: event_type, data })
          }
        }
      }
    } else if trimmed.has_prefix("data:") {
      let data_str = safe_substring(trimmed, 5)
      if data_str != "[DONE]" {
        let data = @json.parse(data_str) catch { _ => Json::null() }
        events.push({ event: "", data })
      }
    }
    i = i + 1
  }
  { events, remaining: remaining.to_string() }
}

///|
fn safe_substring(s : String, start : Int) -> String {
  if start >= s.length() {
    return ""
  }
  let buf = StringBuilder::new()
  let mut idx = 0
  for c in s {
    if idx >= start {
      buf.write_char(c)
    }
    idx = idx + 1
  }
  buf.to_string().trim().to_string()
}
