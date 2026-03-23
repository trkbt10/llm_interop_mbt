///|
/// String helper tests

///|
test "find_substr handles empty needles and misses" {
  assert_eq(find_substr("abcdef", "", 3), Some(3))
  assert_eq(find_substr("abcdef", "cd", 0), Some(2))
  assert_eq(find_substr("abcdef", "gh", 0), None)
}

///|
test "parse_url handles full URLs, bare hosts, and missing schemes" {
  let (origin1, path1) = parse_url("https://api.openai.com/v1/responses")
  assert_eq(origin1, "https://api.openai.com")
  assert_eq(path1, "/v1/responses")

  let (origin2, path2) = parse_url("localhost:11434")
  assert_eq(origin2, "localhost:11434")
  assert_eq(path2, "")

  let (origin3, path3) = parse_url("api.openai.com/v1")
  assert_eq(origin3, "api.openai.com")
  assert_eq(path3, "/v1")
}

///|
test "parse_data_url and split_lines cover valid and invalid branches" {
  assert_eq(parse_data_url("https://example.com/image.png"), None)
  assert_eq(parse_data_url("data:text/plain,abc"), None)
  assert_eq(parse_data_url("data:image/png;"), None)
  assert_eq(parse_data_url("data:image/png;utf8,abc"), None)
  match parse_data_url("data:image/png;base64,iVBORw0KGgo=") {
    Some((media_type, data)) => {
      assert_eq(media_type, "image/png")
      assert_eq(data, "iVBORw0KGgo=")
    }
    None => fail("Expected valid data URL")
  }

  assert_eq(split_lines("a\r\nb\nc"), ["a", "b", "c"])
}
