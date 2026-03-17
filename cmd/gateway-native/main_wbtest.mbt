///|
/// Tests for gateway native functions

test "expand_env expands environment variable" {
  @sys.set_env_var("TEST_VAR_12345", "test_value")
  let result = expand_env("${TEST_VAR_12345}")
  assert_eq(result, "test_value")
  @sys.unset_env_var("TEST_VAR_12345")
}

test "expand_env returns original if not env var format" {
  assert_eq(expand_env("plain_string"), "plain_string")
  assert_eq(expand_env("$NOT_ENV"), "$NOT_ENV")
  assert_eq(expand_env("{NOT_ENV}"), "{NOT_ENV}")
}

test "expand_env returns empty for missing env var" {
  let result = expand_env("${NONEXISTENT_VAR_99999}")
  assert_eq(result, "")
}
