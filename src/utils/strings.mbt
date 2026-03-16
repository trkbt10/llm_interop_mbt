///|
/// Find substring index starting from given position
pub fn find_substr(s : String, needle : String, start : Int) -> Int? {
  let s_len = s.length()
  let n_len = needle.length()
  if n_len == 0 {
    return Some(start)
  }
  for i = start; i <= s_len - n_len; i = i + 1 {
    let mut found = true
    for j = 0; j < n_len; j = j + 1 {
      if s[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return Some(i)
    }
  }
  None
}

///|
/// Parse URL into (origin, path)
/// e.g., "https://api.openai.com/v1" -> ("https://api.openai.com", "/v1")
pub fn parse_url(url : String) -> (String, String) {
  let proto_end = match find_substr(url, "://", 0) {
    Some(i) => i + 3
    None => 0
  }
  let path_start = match find_substr(url, "/", proto_end) {
    Some(i) => i
    None => url.length()
  }
  let origin_buf = StringBuilder::new()
  for i = 0; i < path_start; i = i + 1 {
    origin_buf.write_char(url[i].to_int().unsafe_to_char())
  }
  let path_buf = StringBuilder::new()
  for i = path_start; i < url.length(); i = i + 1 {
    path_buf.write_char(url[i].to_int().unsafe_to_char())
  }
  (origin_buf.to_string(), path_buf.to_string())
}

///|
/// Split string into lines, handling both LF and CRLF line endings
pub fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for c in s {
    if c == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else if c == '\r' {
      // Ignore CR (CRLF support)
      continue
    } else {
      buf.write_char(c)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}
