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
test "ToolCallRequest::builtin creates builtin instance" {
  let call = ToolCallRequest::builtin(
    id="mcp_123",
    type_="mcp_call",
    payload={ "server_label": "docs", "arguments": "{\"topic\":\"MoonBit\"}" },
    name="lookup_docs",
  )
  assert_eq(call.kind, ToolCallKind::Builtin(builtin_type="mcp_call"))
  inspect(call.id, content="mcp_123")
  inspect(call.name, content="lookup_docs")
  match call.arguments {
    { "server_label": String(label), .. } => assert_eq(label, "docs")
    _ => fail("Expected builtin payload")
  }
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
test "ToolDefinition::builtin creates provider builtin instance" {
  let tool = ToolDefinition::builtin(
    type_="code_execution_20250825",
    name="code_execution",
    config={ "allowed_callers": Json::array([Json::string("direct")]) },
  )
  inspect(tool.name, content="code_execution")
  match tool.kind {
    ToolDefinitionKind::Builtin(builtin_type~, config~) => {
      assert_eq(builtin_type, "code_execution_20250825")
      match config {
        { "allowed_callers": Array(values), .. } =>
          assert_eq(values.length(), 1)
        _ => fail("Expected config payload")
      }
    }
    _ => fail("Expected Builtin kind")
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

///|
test "ContentPart enum covers all multimodal types" {
  // Verify all ContentPart variants can be constructed
  let parts : Array[ContentPart] = [
    ContentPart::Text("hello"),
    ContentPart::ImageUrl(url="https://img.png", detail=Some("auto")),
    ContentPart::ImageBase64(data="abc", media_type="image/png"),
    ContentPart::Audio(data="base64audio", format="wav"),
    ContentPart::Document(
      data="base64pdf",
      media_type="application/pdf",
      title=Some("doc.pdf"),
    ),
    ContentPart::FileRef(file_id="file_abc", media_type=Some("application/pdf")),
    ContentPart::Video(data="base64video", media_type="video/mp4"),
  ]
  inspect(parts.length(), content="7")
}

///|
test "ResponseContentPart enum covers all output types" {
  let parts : Array[ResponseContentPart] = [
    ResponseContentPart::OutputText("hello"),
    ResponseContentPart::OutputImage(url="https://img.png"),
    ResponseContentPart::Refusal("cannot help"),
    ResponseContentPart::Thinking(text="let me think..."),
    ResponseContentPart::RedactedThinking(data="encrypted..."),
    ResponseContentPart::CodeExecution(language="python", code="print(1)"),
    ResponseContentPart::CodeResult(outcome="OUTCOME_OK", output="1"),
    ResponseContentPart::AudioOutput(data="base64audio", transcript="hello"),
  ]
  inspect(parts.length(), content="8")
}

///|
test "RichTextResponse with content_parts" {
  let rich = RichTextResponse::new(
    content="Hello",
    content_parts=Some([
      ResponseContentPart::OutputText("Hello"),
      ResponseContentPart::OutputImage(url="https://img.png"),
    ]),
  )
  inspect(rich.content, content="Hello")
  match rich.content_parts {
    Some(parts) => inspect(parts.length(), content="2")
    None => fail("Expected content_parts")
  }
}
