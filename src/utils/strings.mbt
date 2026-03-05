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
