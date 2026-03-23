///|
/// Testdata path helper coverage

///|
test "testdata helpers handle existing fixtures and missing paths" {
  let existing = "testdata/openai/chat_completions/live_multi_toolcall_20250321.json"
  assert_true(file_readable(existing))
  assert_eq(resolve_testdata_path(existing), existing)
  assert_true(read_testdata(existing).contains("tool_calls"))

  let missing = "testdata/definitely-missing-fixture.json"
  assert_false(file_readable(missing))
  assert_eq(resolve_testdata_path(missing), missing)
}
