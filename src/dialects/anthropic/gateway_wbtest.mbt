///|
test "anthropic_resolve_completion requires a model" {
  let body = "{\"model\":\"claude-sonnet-4-6\",\"messages\":[]}"
  match anthropic_resolve_completion("POST", "/v1/messages", body) {
    Some((dialect, model, resolved_body)) => {
      assert_eq(dialect, "anthropic")
      assert_eq(model, "claude-sonnet-4-6")
      assert_eq(resolved_body, body)
    }
    None => fail("Expected Anthropic completion route")
  }

  assert_eq(anthropic_resolve_completion("POST", "/v1/messages", "{}"), None)
}
