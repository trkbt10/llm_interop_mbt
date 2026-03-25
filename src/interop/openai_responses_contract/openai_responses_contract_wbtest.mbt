///|
test "private responses contract helpers cover embedded results and synthesized ids" {
  match
    parse_embedded_responses_tool_result_item(
      "call_1", "{\"type\":\"computer_call_output\",\"output\":\"ok\"}",
    ) {
    Some({ "type": "computer_call_output", "id": "call_1", .. }) => ()
    _ => fail("Expected embedded builtin result with synthesized id")
  }
  match
    parse_embedded_responses_tool_result_item(
      "call_1", "{\"type\":\"not_supported\"}",
    ) {
    None => ()
    Some(_) => fail("Expected unsupported embedded item to stay unsupported")
  }
  match parse_embedded_responses_tool_result_item("call_1", "[]") {
    None => ()
    Some(_) => fail("Expected non-object embedded item to stay plain output")
  }

  assert_eq(
    ensure_tool_result_item_id(
      Json::string("raw"),
      "computer_call_output",
      "id_1",
    ),
    Json::string("raw"),
  )

  let builtin_item = build_responses_builtin_tool_item(
    "local_shell_call",
    "shell_1",
    "shell",
    Json::string("ignored"),
    statuses=[@types.ToolCallStatus::InProgress],
  )
  match builtin_item {
    {
      "type": "local_shell_call",
      "id": "shell_1",
      "name": "shell",
      "status": "in_progress",
      ..
    } => ()
    _ => fail("Expected synthesized builtin item")
  }
}

///|
test "panic messages_to_responses_input rejects unsupported embedded tool results" {
  ignore(
    messages_to_responses_input([
      @types.ModelMessage::ToolResult(
        tool_call_id="call_1",
        content="{\"type\":\"not_supported\"}",
      ),
    ]),
  )
}

///|
test "messages_to_responses_input keeps plain tool outputs as function_call_output" {
  let input = messages_to_responses_input([
    @types.ModelMessage::ToolResult(tool_call_id="call_1", content="[]"),
  ])
  match input[0] {
    { "type": "function_call_output", "call_id": "fc_1", "output": "[]", .. } =>
      ()
    _ => fail("Expected plain tool output fallback")
  }
}

///|
test "messages_to_responses_input canonicalizes assistant tool call ids to Responses ids" {
  let input = messages_to_responses_input([
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="call_lookup", name="lookup", arguments={
          "label": "moonbit",
        }),
      ]),
    ),
  ])
  match input[0] {
    { "type": "function_call", "call_id": "fc_lookup", "name": "lookup", .. } =>
      ()
    _ => fail("Expected canonical Responses function_call id")
  }
}

///|
test "private responses contract helpers cover rich output decomposition and reasoning" {
  match
    rich_parts_for_responses_output(
      @types.RichTextResponse::from_parts(content="", content_parts=[]),
    ) {
    [] => ()
    _ => fail("Expected empty rich parts fallback")
  }
  match
    rich_parts_for_responses_output(
      @types.RichTextResponse::from_parts(content="plain", content_parts=[]),
    ) {
    [@types.ResponseContentPart::OutputText(text)] => assert_eq(text, "plain")
    _ => fail("Expected text rich parts fallback")
  }

  assert_eq(tool_trace_status_to_json([]), Json::string("completed"))
  assert_eq(
    tool_trace_status_to_json([@types.ToolCallStatus::InProgress]),
    Json::string("in_progress"),
  )

  let reasoning_json = build_responses_reasoning_item("Step 1: analyze...")
  match reasoning_json {
    { "type": "reasoning", "summary": Array(summary), .. } =>
      assert_eq(summary.length(), 1)
    _ => fail("Expected reasoning item")
  }

  let encrypted_reasoning = build_responses_reasoning_item(
    "",
    encrypted_content=Some("enc_blob"),
  )
  match encrypted_reasoning {
    {
      "type": "reasoning",
      "summary": Array(summary),
      "encrypted_content": "enc_blob",
      ..
    } => assert_eq(summary.length(), 0)
    _ => fail("Expected encrypted reasoning item")
  }

  let tool_outputs = build_responses_output_from_tool_calls([
    @types.ToolCallRequest::builtin(
      id="builtin_ws",
      type_=@types.web_search_tool_name(),
      payload={ "query": "moonbit" },
      name=@types.web_search_tool_name(),
    ),
    @types.ToolCallRequest::builtin(
      id="builtin_shell",
      type_="local_shell_call",
      payload={ "command": "pwd" },
      name="local_shell_call",
    ),
  ])
  assert_eq(tool_outputs.length(), 2)
  match tool_outputs[0] {
    { "type": "web_search_call", "id": "builtin_ws", .. } => ()
    _ => fail("Expected builtin web search alias")
  }
  match tool_outputs[1] {
    { "type": "local_shell_call", "id": "builtin_shell", .. } => ()
    _ => fail("Expected builtin shell output")
  }

  let (message_parts, trace_outputs, reasoning_outputs) = decompose_responses_rich_content(
    [
      @types.ResponseContentPart::OutputText("Hello"),
      @types.ResponseContentPart::Refusal("No"),
      @types.ResponseContentPart::RedactedThinking(data="ENC"),
      @types.ResponseContentPart::CodeExecution(
        language="python",
        code="print(1)",
      ),
      @types.ResponseContentPart::CodeResult(outcome="OUTCOME_OK", output="1"),
      @types.ResponseContentPart::AudioOutput(data="AUDIO", transcript="spoken"),
    ],
    [
      @types.ResponseAnnotation::url_citation(
        url="https://example.com",
        start_index=0,
        end_index=5,
        title=None,
      ),
    ],
    [
      @types.ToolCallTrace::new(
        id="ws_1",
        name=@types.web_search_tool_name(),
        kind=@types.ToolCallKind::WebSearch,
        statuses=[@types.ToolCallStatus::Searching],
        arguments={ "query": "moonbit" },
      ),
      @types.ToolCallTrace::new(
        id="shell_1",
        name="local_shell_call",
        kind=@types.ToolCallKind::Builtin(builtin_type="local_shell_call"),
        statuses=[@types.ToolCallStatus::Completed],
        arguments={ "command": "pwd" },
      ),
    ],
  )
  assert_eq(message_parts.length(), 5)
  assert_eq(trace_outputs.length(), 2)
  assert_eq(reasoning_outputs.length(), 1)
}
