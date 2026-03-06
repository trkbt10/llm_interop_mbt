///|
/// Types package tests

///|
test "ToolCallRequest::new creates instance" {
  let call = ToolCallRequest::new(id="call_123", name="get_weather", arguments={
    "city": "Tokyo",
  })
  inspect(call.id, content="call_123")
  inspect(call.name, content="get_weather")
  assert_eq(call.kind, ToolCallKind::Function)
}

///|
test "ToolCallRequest::default creates empty instance" {
  let call = ToolCallRequest::default()
  inspect(call.id, content="")
  inspect(call.name, content="")
}

///|
test "ToolDefinition::new creates instance" {
  let tool = ToolDefinition::new(name="search", description="Search the web", parameters={
    "type": "object",
  })
  inspect(tool.name, content="search")
  inspect(tool.description, content="Search the web")
  assert_eq(tool.kind, ToolDefinitionKind::Function)
}

///|
test "ToolDefinition::web_search_preview creates builtin instance" {
  let tool = ToolDefinition::web_search_preview(
    search_context_size=Some("medium"),
    user_location_country=Some("US"),
  )
  inspect(tool.name, content="web_search")
  match tool.kind {
    ToolDefinitionKind::WebSearchPreview(
      search_context_size~,
      user_location_country~
    ) => {
      assert_eq(search_context_size, Some("medium"))
      assert_eq(user_location_country, Some("US"))
    }
    _ => fail("Expected WebSearchPreview kind")
  }
}

///|
test "build_json_schema creates valid schema" {
  let schema = build_json_schema(
    type_="object",
    properties={ "name": { "type": "string" } },
    required=["name"],
  )
  match schema {
    { "type": "object", "properties": Object(_), "required": Array(_), .. } =>
      ()
    _ => fail("Expected valid schema")
  }
}
