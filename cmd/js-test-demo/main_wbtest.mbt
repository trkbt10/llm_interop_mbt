///|
test "build_demo_request creates a responses payload suitable for JS target runs" {
  let body = build_demo_request()
  match body {
    {
      "model": "gpt-4.1-mini",
      "input": Array(input),
      "tools": Array(tools),
      ..
    } => {
      assert_eq(input.length(), 2)
      assert_eq(tools.length(), 2)
      match tools[0] {
        { "type": "function", "name": "get_weather", .. } => ()
        _ => fail("Expected first tool to be a function tool")
      }
      match tools[1] {
        { "type": "web_search_preview", .. } => ()
        _ => fail("Expected second tool to be a web search tool")
      }
    }
    _ => fail("Expected Responses API payload")
  }
}

///|
test "render_demo_output includes a readable summary and JSON body" {
  let output = render_demo_output()
  assert_true(output.contains("JS target test demo"))
  assert_true(output.contains("model=gpt-4.1-mini"))
  assert_true(output.contains("\"tools\""))
  assert_true(output.contains("\"get_weather\""))
}
