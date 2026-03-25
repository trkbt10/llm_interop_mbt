///|
test "responses contract covers input and output carriers" {
  let input = messages_to_responses_input([
    @types.ModelMessage::System("System prompt"),
    @types.ModelMessage::User(
      content="ignored",
      name=None,
      content_parts=Some([
        @types.ContentPart::Text("hello"),
        @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
      ]),
    ),
  ])
  assert_eq(input.length(), 2)
  match input[1] {
    { "role": "user", "content": Array(parts), .. } => {
      assert_eq(parts.length(), 2)
      assert_eq(parts[0], { "type": "input_text", "text": "hello" })
      assert_eq(parts[1], {
        "type": "input_file",
        "file_url": "https://example.com/report.pdf",
      })
    }
    _ => fail("Expected responses input")
  }

  let output = model_response_to_responses_output(
    @types.ModelResponse::ToolCallsWithContent(
      tool_calls=[
        @types.ToolCallRequest::new(id="call_1", name="lookup", arguments={
          "q": "moonbit",
        }),
      ],
      rich=@types.RichTextResponse::from_parts(content="before", content_parts=[
        @types.ResponseContentPart::OutputText("before"),
        @types.ResponseContentPart::OutputImage(
          url="https://example.com/image.png",
        ),
      ]),
    ),
  )
  assert_eq(output.length(), 2)
}

///|
test "responses contract wraps response envelopes and builtin item types" {
  assert_true(is_builtin_responses_tool_item_type("computer_call"))
  assert_true(not(is_builtin_responses_tool_item_type("function_call")))

  let json = model_response_to_responses_json(
    @types.ModelResponse::Text("ok"),
    response_id="resp_1",
    model="gpt-4.1-mini",
  )
  match json {
    {
      "id": "resp_1",
      "object": "response",
      "status": "completed",
      "model": "gpt-4.1-mini",
      "output": Array(output),
      ..
    } => assert_eq(output.length(), 1)
    _ => fail("Expected responses envelope")
  }
}
