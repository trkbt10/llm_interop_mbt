///|
/// SSE stream parser whitebox tests

///|
test "safe_substring trims and guards out-of-range starts" {
  assert_eq(safe_substring("  abc  ", 2), "abc")
  assert_eq(safe_substring("abc", 3), "")
  assert_eq(safe_substring("abc", 9), "")
}

///|
test "parse_sse_chunk preserves incomplete trailing lines as remaining" {
  let chunk =
    #|event: response.created
    #|data: {"type":"response.created"}
    #|
    #|event: response.delta
  let parsed = parse_sse_chunk(chunk)
  assert_eq(parsed.events.length(), 1)
  assert_eq(parsed.events[0].event, "response.created")
  assert_eq(parsed.remaining, "event: response.delta")
}

///|
test "parse_sse_chunk maps malformed JSON to null and skips done markers" {
  let malformed_chunk =
    #|data: {oops}
    #|
    #|data: [DONE]
    #|
  let parsed = parse_sse_chunk(malformed_chunk)
  assert_eq(parsed.events.length(), 1)
  assert_eq(parsed.events[0].event, "")
  match parsed.events[0].data {
    Null => ()
    _ => fail("Expected malformed JSON to become null")
  }
  assert_eq(parsed.remaining, "")
}
