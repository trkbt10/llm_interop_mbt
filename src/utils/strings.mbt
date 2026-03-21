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
/// Parse a data: URL into (media_type, base64_data).
/// e.g., "data:image/png;base64,iVBOR..." -> ("image/png", "iVBOR...")
pub fn parse_data_url(url : String) -> (String, String)? {
  if not(url.has_prefix("data:")) {
    return None
  }
  let semicolon = match find_substr(url, ";", 5) {
    Some(i) => i
    None => return None
  }
  // Extract media type: characters between "data:" (index 5) and semicolon
  let media_type = StringBuilder::new()
  for i = 5; i < semicolon; i = i + 1 {
    media_type.write_char(url[i].to_int().unsafe_to_char())
  }
  // Verify "base64," marker after semicolon
  let base64_start = semicolon + 1
  if not(url.length() >= base64_start + 7) {
    return None
  }
  let marker = StringBuilder::new()
  for i = base64_start; i < base64_start + 7; i = i + 1 {
    marker.write_char(url[i].to_int().unsafe_to_char())
  }
  if marker.to_string() != "base64," {
    return None
  }
  // Extract base64 data
  let data_start = base64_start + 7
  let data = StringBuilder::new()
  for i = data_start; i < url.length(); i = i + 1 {
    data.write_char(url[i].to_int().unsafe_to_char())
  }
  Some((media_type.to_string(), data.to_string()))
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
