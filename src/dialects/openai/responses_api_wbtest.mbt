///|
/// Whitebox coverage for Responses API helpers and validation branches

///|
test "messages_to_responses_input covers system, multimodal user parts, assistant tool variants, and fallback tool results" {
  let input = @openai_responses_contract.messages_to_responses_input([
    @types.ModelMessage::System("System prompt"),
    @types.ModelMessage::User(
      content="ignored",
      name=None,
      content_parts=Some([
        @types.ContentPart::ImageUrl(
          url="https://example.com/cat.png",
          detail=Some("high"),
        ),
        @types.ContentPart::ImageBase64(data="AAA", media_type="image/png"),
        @types.ContentPart::Audio(data="AUDIO", format="wav"),
        @types.ContentPart::Document(
          data="PDF",
          media_type="application/pdf",
          title=None,
        ),
        @types.ContentPart::FileRef(
          file_id="file_123",
          media_type=Some("application/pdf"),
        ),
        @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
        @types.ContentPart::Video(data="VIDEO", media_type="video/mp4"),
      ]),
    ),
    @types.ModelMessage::Assistant(
      content="preface",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="call_fn", name="lookup", arguments={
          "q": "moonbit",
        }),
        @types.ToolCallRequest::web_search(
          id="call_ws",
          query=Some("moonbit"),
          queries=None,
        ),
        @types.ToolCallRequest::builtin(
          id="call_builtin",
          type_="computer_call",
          payload={ "cursor": "1" },
          name="computer_call",
        ),
      ]),
    ),
    @types.ModelMessage::Assistant(content="tail", tool_calls=None),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_out",
      content="plain output",
    ),
  ])

  assert_eq(input.length(), 8)
  assert_eq(input[0], { "role": "system", "content": "System prompt" })
  match input[1] {
    { "role": "user", "content": Array(parts), .. } => {
      assert_eq(parts.length(), 7)
      match parts[0] {
        {
          "type": "input_image",
          "image_url": "https://example.com/cat.png",
          "detail": "high",
          ..
        } => ()
        _ => fail("Expected detailed image URL block")
      }
      assert_eq(parts[1], {
        "type": "input_image",
        "image_url": "data:image/png;base64,AAA",
      })
      assert_eq(parts[2], {
        "type": "input_audio",
        "data": "AUDIO",
        "format": "wav",
      })
      assert_eq(parts[3], {
        "type": "input_file",
        "file_data": "data:application/pdf;base64,PDF",
      })
      assert_eq(parts[4], { "type": "input_file", "file_id": "file_123" })
      assert_eq(parts[5], {
        "type": "input_file",
        "file_url": "https://example.com/report.pdf",
      })
      assert_eq(parts[6], {
        "type": "input_file",
        "file_data": "data:video/mp4;base64,VIDEO",
      })
    }
    _ => fail("Expected multimodal user input")
  }
  assert_eq(input[2], { "role": "assistant", "content": "preface" })
  match input[3] {
    {
      "type": "function_call",
      "call_id": "fc_fn",
      "name": "lookup",
      "arguments": String(arguments),
      ..
    } => assert_true(arguments.contains("\"q\""))
    _ => fail("Expected function call output item")
  }
  match input[4] {
    { "type": "web_search_call", "id": "call_ws", .. } => ()
    _ => fail("Expected web search output item")
  }
  match input[5] {
    {
      "type": "computer_call",
      "id": "call_builtin",
      "name": "computer_call",
      ..
    } => ()
    _ => fail("Expected builtin output item")
  }
  assert_eq(input[6], { "role": "assistant", "content": "tail" })
  match input[7] {
    {
      "type": "function_call_output",
      "call_id": "fc_out",
      "output": "plain output",
      ..
    } => ()
    _ => fail("Expected fallback tool result item")
  }

  let fallback = @openai_responses_contract.messages_to_responses_input([
    @types.ModelMessage::ToolResult(
      tool_call_id="call_out",
      content="plain output",
    ),
  ])
  assert_eq(fallback[0], {
    "type": "function_call_output",
    "call_id": "fc_out",
    "output": "plain output",
  })
}

///|
test "output builders cover error responses, builtin web-search alias, rich decomposition, and request bodies without tools" {
  assert_eq(
    @openai_responses_contract.model_response_to_responses_output(
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::new(
          type_="invalid_request_error",
          message="boom",
        ),
      ),
    ).length(),
    0,
  )
  assert_eq(
    @openai_responses_contract.model_response_to_responses_output(
      @types.ModelResponse::ModelError("boom"),
    ).length(),
    0,
  )
  assert_eq(
    @openai_responses_contract.model_response_to_responses_output(
      @types.ModelResponse::RateLimited(retry_after=3),
    ).length(),
    0,
  )

  match
    @openai_responses_contract.model_response_to_responses_json(
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::new(
          type_="invalid_request_error",
          message="boom",
          code=Some(400),
          payload=Some({ "field": "messages" }),
        ),
      ),
      response_id="resp_fail",
      model="gpt-4.1",
    ) {
    {
      "error": {
        "type": "invalid_request_error",
        "message": "boom",
        "code": Number(code, ..),
        "payload": { "field": "messages", .. },
        ..
      },
      ..
    } => assert_eq(code.to_int(), 400)
    _ => fail("Expected structured failure response json")
  }
  match
    @openai_responses_contract.model_response_to_responses_json(
      @types.ModelResponse::ModelError("boom"),
      response_id="resp_err",
      model="gpt-4.1",
    ) {
    { "error": { "type": "error", "message": "boom", .. }, .. } => ()
    _ => fail("Expected error response json")
  }
  match
    @openai_responses_contract.model_response_to_responses_json(
      @types.ModelResponse::RateLimited(retry_after=9),
      response_id="resp_rate",
      model="gpt-4.1",
    ) {
    {
      "error": {
        "type": "rate_limit_error",
        "retry_after": Number(retry_after, ..),
        ..
      },
      ..
    } => assert_eq(retry_after.to_int(), 9)
    _ => fail("Expected rate limit response json")
  }

  assert_eq(
    build_responses_api_body(
      "gpt-4.1",
      [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
      [],
    ),
    {
      "model": "gpt-4.1",
      "input": Json::array([{ "role": "user", "content": "Hi" }]),
    },
  )
}

///|
test "responses tool builders cover function, web search, and generic builtin helpers" {
  match
    tool_to_responses_api_json(
      @types.ToolDefinition::new(name="search", description="Search the web", parameters={
        "type": "object",
        "properties": {},
      }),
    ) {
    {
      "type": "function",
      "name": "search",
      "description": "Search the web",
      ..
    } => ()
    _ => fail("Expected function tool json")
  }

  match
    tool_to_responses_api_json(
      @types.ToolDefinition::web_search_preview(
        search_context_size=Some("medium"),
        user_location_country=Some("US"),
      ),
    ) {
    {
      "type": "web_search_preview",
      "search_context_size": "medium",
      "user_location": { "type": "approximate", "country": "US", .. },
      ..
    } => ()
    _ => fail("Expected web search tool json")
  }

  match
    tool_to_responses_api_json(
      @types.ToolDefinition::builtin(type_="code_interpreter", config={
        "container": { "type": "auto" },
      }),
    ) {
    { "type": "code_interpreter", "container": { "type": "auto", .. }, .. } =>
      ()
    _ => fail("Expected generic builtin tool json")
  }
}

///|
test "parser helpers cover provider errors, builtin traces, reasoning parsing, annotations, and mixed outputs" {
  match parse_responses_api_response({ "error": { "message": "boom" } }) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "error")
      assert_eq(failure.message, "boom")
    }
    _ => fail("Expected provider error")
  }
  match parse_responses_api_response({}) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "parse_error")
      assert_eq(failure.message, "Unknown response format")
    }
    _ => fail("Expected unknown format error")
  }

  match
    parse_responses_output([
      {
        "type": "message",
        "content": Json::array([
          {
            "type": "output_text",
            "text": "Hello",
            "annotations": Json::array([
              {
                "type": "url_citation",
                "url": "https://example.com",
                "start_index": 0,
                "end_index": 5,
              },
            ]),
          },
          { "type": "refusal", "refusal": "No" },
        ]),
      },
      {
        "type": "function_call",
        "id": "call_id_only",
        "name": "lookup",
        "arguments": "{\"q\":\"moonbit\"}",
      },
      {
        "type": "function_call",
        "id": "call_second",
        "name": "lookup_second",
        "arguments": "{}",
      },
      { "type": "web_search_call", "id": "ws_1", "status": "in_progress" },
      {
        "type": "reasoning",
        "content": Json::array([{ "type": "text", "text": "Thinking" }]),
      },
      {
        "type": "reasoning",
        "summary": Json::array([{ "type": "summary_text", "text": "Summary" }]),
        "encrypted_content": "ENC",
      },
      { "type": "local_shell_call", "id": "shell_1", "status": "calling" },
      {
        "type": "tool_search_output",
        "approval_request_id": "trace_1",
        "status": "searching",
      },
    ]) {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 3)
      assert_eq(tool_calls[0].id, "call_id_only")
      assert_eq(tool_calls[0].arguments, { "q": "moonbit" })
      assert_eq(tool_calls[1].id, "call_second")
      assert_eq(tool_calls[2].id, "shell_1")
      assert_eq(rich.content, "Hello")
      match rich.content_parts {
        Some(parts) => assert_true(parts.length() >= 4)
        None => fail("Expected structured rich content")
      }
      assert_eq(rich.annotations.length(), 1)
      assert_eq(rich.tool_traces.length(), 2)
    }
    _ => fail("Expected mixed tool-call response")
  }

  let reasoning_parts : Array[@types.ResponseContentPart] = []
  assert_true(
    append_response_reasoning_item(
      {
        "summary": Json::array([{ "type": "summary_text", "text": "Summary" }]),
        "encrypted_content": "ENC2",
      },
      reasoning_parts,
    ),
  )
  assert_eq(reasoning_parts.length(), 2)
  let reasoning_parts_with_content : Array[@types.ResponseContentPart] = []
  assert_true(
    append_response_reasoning_item(
      {
        "content": Json::array([{ "type": "reasoning_text", "text": "Chain" }]),
        "encrypted_content": "ENC3",
      },
      reasoning_parts_with_content,
    ),
  )
  assert_eq(reasoning_parts_with_content.length(), 2)
  let empty_reasoning_parts : Array[@types.ResponseContentPart] = []
  assert_false(append_response_reasoning_item({}, empty_reasoning_parts))

  let annotations = parse_response_annotation_json(
    Json::array([
      {
        "type": "url_citation",
        "url": "https://example.com",
        "start_index": 1,
        "end_index": 3,
      },
      {
        "type": "char_location",
        "cited_text": "MoonBit",
        "document_index": 0,
        "document_title": "Guide",
        "file_id": "file_guide",
        "start_char_index": 10,
        "end_char_index": 17,
        "start_index": 4,
        "end_index": 11,
      },
    ]),
  )
  assert_eq(annotations.length(), 2)

  let trace = parse_web_search_trace({ "id": "ws_2" }, "ws_2")
  assert_eq(trace.statuses.length(), 0)
  assert_eq(trace.arguments, {})
  let searching_trace = parse_web_search_trace(
    { "id": "ws_3", "status": "searching" },
    "ws_3",
  )
  assert_eq(searching_trace.statuses, [@types.ToolCallStatus::Searching])

  let builtin_named = parse_builtin_trace(
    { "id": "trace_2", "name": "shell", "status": "completed" },
    "local_shell_call",
  )
  assert_eq(builtin_named.name, "shell")
  let builtin_fallback = parse_builtin_trace(
    { "id": "trace_3", "status": "completed" },
    "local_shell_call",
  )
  assert_eq(builtin_fallback.name, "local_shell_call")
  let builtin_call = parse_builtin_tool_call(
    { "call_id": "call_2", "status": "interpreting" },
    "mcp_call",
  )
  assert_eq(builtin_call.id, "call_2")
  assert_eq(builtin_call.name, "mcp_call")

  assert_eq(extract_responses_tool_item_id({ "call_id": "call_3" }), "call_3")
  assert_eq(parse_responses_tool_statuses({ "status": "searching" }), [
    @types.ToolCallStatus::Searching,
  ])
  assert_eq(parse_responses_tool_statuses({ "status": "calling" }), [
    @types.ToolCallStatus::InProgress,
  ])
  assert_eq(parse_responses_tool_statuses({}), [])
}

///|
test "panic extract_responses_tool_item_id rejects missing ids" {
  extract_responses_tool_item_id({}) |> ignore
}

///|
test "panic parse_responses_output rejects unknown output item types" {
  parse_responses_output([{ "type": "unknown_item" }]) |> ignore
}

///|
test "panic append_response_message_contents rejects unknown content types" {
  append_response_message_contents([{ "type": "ignored" }], [], []) |> ignore
}

///|
test "panic append_response_reasoning_item rejects unknown reasoning blocks" {
  append_response_reasoning_item(
    { "content": Json::array([{ "type": "ignored" }]) },
    [],
  )
  |> ignore
}

///|
test "panic parse_response_annotation_json rejects unknown annotations" {
  parse_response_annotation_json({ "type": "ignored" }) |> ignore
}

///|
test "panic parse_responses_api_response rejects malformed function call arguments" {
  parse_responses_api_response({
    "id": "resp_bad",
    "model": "gpt-4.1",
    "status": "completed",
    "output": Json::array([
      {
        "type": "function_call",
        "call_id": "call_bad",
        "name": "lookup",
        "arguments": "not-json",
      },
    ]),
  })
  |> ignore
}
