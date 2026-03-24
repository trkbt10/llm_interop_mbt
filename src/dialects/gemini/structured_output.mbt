///|
/// Structured-output canonicalization helpers for Gemini text responses.
///
/// Gemini sometimes returns structured output wrapped in provider-specific
/// envelopes such as:
///   {"tool_name_response":{"url":"..."}}
///   {"tool_name_response":{"content":"{\"url\":\"...\"}"}}
/// and may fence JSON in ```json blocks. Dialect-level canonicalization keeps
/// the Responses-based intermediate closer to the caller's intent.

///|
fn join_fragments(fragments : Array[String], separator : String) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for fragment in fragments {
    if not(first) {
      buf.write_string(separator)
    }
    buf.write_string(fragment)
    first = false
  }
  buf.to_string()
}

///|
fn strip_structured_output_code_fence(text : String) -> String {
  let trimmed = text.trim(chars=" \n\r\t").to_string()
  guard trimmed.has_prefix("```") && trimmed.has_suffix("```") else {
    return trimmed
  }
  let lines = @utils.split_lines(trimmed)
  guard lines.length() >= 2 else { return trimmed }
  let inner : Array[String] = []
  for i in 1..<(lines.length() - 1) {
    inner.push(lines[i])
  }
  join_fragments(inner, "\n").trim(chars=" \n\r\t").to_string()
}

///|
fn try_parse_structured_output_text(text : String) -> Json? {
  let candidate = strip_structured_output_code_fence(text)
  if candidate.length() == 0 {
    return None
  }
  Some(@json.parse(candidate)) catch {
    _ => None
  }
}

///|
fn unwrap_structured_output_json_once(value : Json) -> Json? {
  match value {
    Object(fields) if fields.length() == 1 => {
      let entries = fields.to_array()
      let (key, inner) = entries[0]
      if key == "content" {
        match inner {
          String(text) => return try_parse_structured_output_text(text)
          _ => ()
        }
      }
      if key.has_suffix("_response") {
        match inner {
          String(text) => return try_parse_structured_output_text(text)
          Object(obj) => {
            match obj.get("content") {
              Some(String(text)) =>
                match try_parse_structured_output_text(text) {
                  Some(parsed) => return Some(parsed)
                  None => ()
                }
              _ => ()
            }
            return Some(inner)
          }
          _ => return Some(inner)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn normalize_structured_output_json(value : Json) -> Json {
  let mut current = value
  for _ in 0..<8 {
    match unwrap_structured_output_json_once(current) {
      Some(next) => current = next
      None => return current
    }
  }
  current
}

///|
fn try_normalize_structured_output_text(text : String) -> String? {
  match try_parse_structured_output_text(text) {
    Some(json) => Some(normalize_structured_output_json(json).stringify())
    None => None
  }
}

///|
fn normalize_structured_output_text(text : String) -> String {
  match try_normalize_structured_output_text(text) {
    Some(normalized) => normalized
    None => text
  }
}

///|
fn try_normalize_structured_output_fragments(
  fragments : Array[String],
  separator : String,
) -> String? {
  if fragments.length() == 0 {
    return None
  }
  let raw_joined = join_fragments(fragments, "")
  match try_normalize_structured_output_text(raw_joined) {
    Some(normalized) => Some(normalized)
    None =>
      try_normalize_structured_output_text(join_fragments(fragments, separator))
  }
}

///|
fn normalize_structured_output_fragments(
  fragments : Array[String],
  separator : String,
) -> String {
  match try_normalize_structured_output_fragments(fragments, separator) {
    Some(normalized) => normalized
    None => join_fragments(fragments, separator)
  }
}
