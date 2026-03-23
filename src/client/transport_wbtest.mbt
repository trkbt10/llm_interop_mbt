///|
/// Whitebox coverage for transport helpers

///|
async test "transport helpers read streams and decode invalid utf8 lossily" {
  let reader = MockStreamReader::from_strings(["Hello", " ", "stream"])
  let text = read_all_from_stream(reader)
  assert_eq(text, "Hello stream")

  let timeout_reader = TimeoutStreamReader::new()
  let timeout_text = read_all_from_stream(timeout_reader)
  assert_eq(timeout_text, "")

  let invalid = Bytes::make(2, b'\xFF')
  assert_eq(bytes_to_string_lossy(invalid), "")
}
