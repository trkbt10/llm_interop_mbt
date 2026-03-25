///|
/// Whitebox coverage for Anthropic protocol helpers and normalization branches

///|
test "message builders cover named users, multimodal parts, tool results, and explicit body fields" {
  assert_eq(message_to_json(@types.ModelMessage::System("You are Claude")), {
    "role": "system",
    "content": "You are Claude",
  })

  let named_user = message_to_json(
    @types.ModelMessage::User(
      content="ignored",
      name=Some("alice"),
      content_parts=Some([
        @types.ContentPart::Text("Look"),
        @types.ContentPart::ImageUrl(
          url="https://example.com/cat.png",
          detail=None,
        ),
        @types.ContentPart::ImageBase64(data="BASE64", media_type="image/png"),
        @types.ContentPart::Document(
          data="PDF",
          media_type="application/pdf",
          title=None,
        ),
        @types.ContentPart::FileRef(
          file_id="file_123",
          media_type=Some("application/pdf"),
        ),
      ]),
    ),
  )
  match named_user {
    { "role": "user", "name": "alice", "content": Array(parts), .. } => {
      assert_eq(parts.length(), 5)
      assert_eq(parts[0], { "type": "text", "text": "Look" })
      assert_eq(parts[1], {
        "type": "image",
        "source": { "type": "url", "url": "https://example.com/cat.png" },
      })
      assert_eq(parts[2], {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/png",
          "data": "BASE64",
        },
      })
      assert_eq(parts[3], {
        "type": "document",
        "source": {
          "type": "base64",
          "media_type": "application/pdf",
          "data": "PDF",
        },
      })
      assert_eq(parts[4], {
        "type": "document",
        "source": { "type": "file", "file_id": "file_123" },
      })
    }
    _ => fail("Expected named multimodal user")
  }

  assert_eq(
    message_to_json(
      @types.ModelMessage::User(
        content="plain",
        name=Some("bob"),
        content_parts=None,
      ),
    ),
    { "role": "user", "content": "plain", "name": "bob" },
  )
  assert_eq(
    message_to_json(
      @types.ModelMessage::User(
        content="plain-no-name",
        name=None,
        content_parts=None,
      ),
    ),
    { "role": "user", "content": "plain-no-name" },
  )

  assert_eq(
    message_to_json(
      @types.ModelMessage::Assistant(content="done", tool_calls=None),
    ),
    { "role": "assistant", "content": "done" },
  )

  assert_eq(
    message_to_json(
      @types.ModelMessage::ToolResult(tool_call_id="toolu_1", content="42"),
    ),
    {
      "role": "user",
      "content": Json::array([
        { "type": "tool_result", "tool_use_id": "toolu_1", "content": "42" },
      ]),
    },
  )

  let messages = messages_to_json([
    @types.ModelMessage::System("skip"),
    @types.ModelMessage::User(
      content="ignored",
      name=None,
      content_parts=Some([@types.ContentPart::Text("payload")]),
    ),
    @types.ModelMessage::Assistant(
      content="preface",
      tool_calls=Some([
        @types.ToolCallRequest::new(id="toolu_2", name="lookup", arguments={
          "q": "moonbit",
        }),
      ]),
    ),
    @types.ModelMessage::Assistant(content="tail", tool_calls=None),
    @types.ModelMessage::ToolResult(tool_call_id="toolu_2", content="ok"),
  ])
  assert_eq(messages.length(), 4)
  assert_eq(messages[0], {
    "role": "user",
    "content": Json::array([{ "type": "text", "text": "payload" }]),
  })
  match messages[1] {
    { "role": "assistant", "content": Array(parts), .. } => {
      assert_eq(parts.length(), 2)
      assert_eq(parts[0], { "type": "text", "text": "preface" })
      match parts[1] {
        { "type": "tool_use", "id": "toolu_2", "name": "lookup", .. } => ()
        _ => fail("Expected tool_use part")
      }
    }
    _ => fail("Expected assistant with tool use")
  }
  assert_eq(messages[2], { "role": "assistant", "content": "tail" })
  assert_eq(messages[3], {
    "role": "user",
    "content": Json::array([
      { "type": "tool_result", "tool_use_id": "toolu_2", "content": "ok" },
    ]),
  })

  let body = build_body(
    "claude-sonnet",
    [@types.ModelMessage::User(content="Hi", name=None, content_parts=None)],
    [
      @types.ToolDefinition::new(name="lookup", description="Search", parameters={
        "type": "object",
      }),
    ],
    max_tokens=Some(123),
    system="Override system",
    temperature=Some(0.4),
    response_format=Some(@types.ResponseFormat::JsonObject),
  )
  match body {
    {
      "model": "claude-sonnet",
      "max_tokens": Number(max_tokens, ..),
      "system": "Override system",
      "temperature": Number(temperature, ..),
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": { "type": "object", "additionalProperties": False, .. },
          ..
        },
        ..
      },
      "tools": Array(tools),
      ..
    } => {
      assert_eq(max_tokens.to_int(), 123)
      assert_eq(temperature, 0.4)
      assert_eq(tools.length(), 1)
    }
    _ => fail("Expected Anthropic body with explicit fields")
  }
}

///|
test "private protocol helpers cover builtin tool, code execution, and trace updates" {
  assert_eq(build_builtin_tool_json("builtin_alpha", "", Json::null()), {
    "type": "builtin_alpha",
  })

  match
    build_code_execution_input_part("code_execution", { "code": "print(1)" }) {
    Some(@types.ResponseContentPart::CodeExecution(language~, code~)) => {
      assert_eq(language, "python")
      assert_eq(code, "print(1)")
    }
    _ => fail("Expected code execution part")
  }
  match
    build_code_execution_input_part("bash_code_execution", {
      "command": "ls -la",
    }) {
    Some(@types.ResponseContentPart::CodeExecution(language~, code~)) => {
      assert_eq(language, "bash")
      assert_eq(code, "ls -la")
    }
    _ => fail("Expected bash code execution part")
  }
  assert_eq(
    build_code_execution_input_part("text_editor_code_execution", {
      "edit": "replace",
    }),
    None,
  )
  assert_eq(build_code_execution_input_part("other", {}), None)

  assert_eq(
    build_code_execution_result_part({}),
    @types.ResponseContentPart::CodeResult(
      outcome="success",
      output="Code execution completed (no output)",
    ),
  )
  assert_eq(
    build_code_execution_result_part({ "stderr": "boom" }),
    @types.ResponseContentPart::CodeResult(
      outcome="failed",
      output="[stderr]\nboom",
    ),
  )

  let traces : Array[@types.ToolCallTrace] = []
  upsert_tool_trace(
    traces,
    "call_1",
    "web_fetch",
    @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
    @types.ToolCallStatus::InProgress,
    Json::object({}),
  )
  assert_eq(traces.length(), 1)
  assert_eq(traces[0].arguments, Json::object({}))

  upsert_tool_trace(
    traces,
    "call_1",
    "web_fetch",
    @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
    @types.ToolCallStatus::Searching,
    { "url": "https://example.com" },
  )
  assert_eq(traces[0].statuses, [
    @types.ToolCallStatus::InProgress,
    @types.ToolCallStatus::Searching,
  ])
  assert_eq(traces[0].arguments, { "url": "https://example.com" })

  upsert_tool_trace(
    traces,
    "call_1",
    "web_fetch",
    @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
    @types.ToolCallStatus::Completed,
    Json::object({}),
  )
  assert_eq(traces[0].statuses, [
    @types.ToolCallStatus::InProgress,
    @types.ToolCallStatus::Searching,
    @types.ToolCallStatus::Completed,
  ])
  assert_eq(traces[0].arguments, { "url": "https://example.com" })

  let tools_json = tools_to_json([
    @types.ToolDefinition::new(name="lookup", description="Search", parameters={
      "type": "object",
    }),
    @types.ToolDefinition::builtin(type_="builtin_beta", name="beta", config={
      "enabled": true,
    }),
  ])
  assert_eq(tools_json.length(), 2)
  match tools_json[1] {
    { "type": "builtin_beta", "name": "beta", "enabled": True, .. } => ()
    _ => fail("Expected builtin tool JSON")
  }
}

///|
test "parse_response covers multiline text, server tools, redacted thinking, and error fallbacks" {
  let response = parse_response({
    "content": Json::array([
      { "type": "text", "text": "first" },
      { "type": "text", "text": "second" },
      { "type": "redacted_thinking", "data": "encrypted" },
      {
        "type": "server_tool_use",
        "id": "srv_1",
        "name": "web_fetch",
        "input": { "url": "https://example.com" },
      },
      {
        "type": "server_tool_use",
        "id": "srv_2",
        "name": "unsupported_tool",
        "input": {},
      },
      {
        "type": "server_tool_use",
        "id": "srv_3",
        "name": "bash_code_execution",
        "input": { "command": "echo hi" },
      },
      {
        "type": "code_execution_tool_result",
        "content": { "stdout": "ok", "stderr": "warn", "return_code": 1 },
      },
      { "type": "text_editor_code_execution_tool_result", "content": {} },
      { "type": "web_fetch_tool_result", "tool_use_id": "srv_1" },
    ]),
    "stop_reason": "end_turn",
  })
  match response {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "first\nsecond")
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 6)
          assert_eq(parts[0], @types.ResponseContentPart::OutputText("first"))
          assert_eq(parts[1], @types.ResponseContentPart::OutputText("second"))
          assert_eq(
            parts[2],
            @types.ResponseContentPart::RedactedThinking(data="encrypted"),
          )
          assert_eq(
            parts[3],
            @types.ResponseContentPart::CodeExecution(
              language="bash",
              code="echo hi",
            ),
          )
          assert_eq(
            parts[4],
            @types.ResponseContentPart::CodeResult(
              outcome="failed",
              output="ok\n[stderr]\nwarn",
            ),
          )
          assert_eq(
            parts[5],
            @types.ResponseContentPart::CodeResult(
              outcome="success",
              output="Code execution completed (no output)",
            ),
          )
        }
        None => fail("Expected rich content parts")
      }
      assert_eq(rich.tool_traces.length(), 2)
      assert_eq(rich.tool_traces[0].name, "web_fetch")
      assert_eq(rich.tool_traces[0].statuses, [
        @types.ToolCallStatus::InProgress,
        @types.ToolCallStatus::Completed,
      ])
      assert_eq(rich.tool_traces[0].arguments, { "url": "https://example.com" })
      assert_eq(rich.tool_traces[1].name, "unsupported_tool")
      assert_eq(
        rich.tool_traces[1].kind,
        @types.ToolCallKind::Builtin(builtin_type="unsupported_tool"),
      )
    }
    _ => fail("Expected rich text response")
  }

  match parse_response({ "content": "bad", "stop_reason": "end_turn" }) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "parse_error")
      assert_eq(failure.message, "Invalid content format")
    }
    _ => fail("Expected invalid content error")
  }
  match parse_response({ "error": { "message": "boom" } }) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "api_error")
      assert_eq(failure.message, "boom")
    }
    _ => fail("Expected provider error")
  }
  match parse_response({}) {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "parse_error")
      assert_eq(failure.message, "Unknown response format")
    }
    _ => fail("Expected unknown format error")
  }
}

///|
test "panic message_to_json rejects unsupported AnthropIc input carriers" {
  ignore(
    message_to_json(
      @types.ModelMessage::User(
        content="ignored",
        name=None,
        content_parts=Some([
          @types.ContentPart::Audio(data="AUDIO", format="wav"),
        ]),
      ),
    ),
  )
  ignore(
    message_to_json(
      @types.ModelMessage::User(
        content="ignored",
        name=None,
        content_parts=Some([
          @types.ContentPart::FileUrl(url="https://example.com/report.pdf"),
        ]),
      ),
    ),
  )
  ignore(
    message_to_json(
      @types.ModelMessage::User(
        content="ignored",
        name=None,
        content_parts=Some([
          @types.ContentPart::Video(data="VIDEO", media_type="video/mp4"),
        ]),
      ),
    ),
  )
}

///|
test "panic private protocol helpers reject malformed builtin config" {
  build_builtin_tool_json("builtin_alpha", "", Json::string("ignored"))
  |> ignore
}

///|
test "panic private protocol helpers reject malformed code execution input" {
  build_code_execution_input_part("code_execution", Json::string("print(1)"))
  |> ignore
}

///|
test "panic private protocol helpers reject malformed bash code execution input" {
  build_code_execution_input_part(
    "bash_code_execution",
    Json::string("echo hi"),
  )
  |> ignore
}

///|
test "panic parse_tool_calls rejects malformed content" {
  parse_tool_calls(Json::null()) |> ignore
}

///|
test "parse_response preserves unknown server tool uses as generic builtin traces" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "server_tool_use",
        "id": "srvtoolu_01MCP",
        "name": "mcp_call",
        "input": { "server_label": "docs" },
      },
    ]),
    "stop_reason": "end_turn",
  }
  match parse_response(response) {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.tool_traces.length(), 1)
      assert_eq(
        rich.tool_traces[0].kind,
        @types.ToolCallKind::Builtin(builtin_type="mcp_call"),
      )
      assert_eq(rich.tool_traces[0].arguments, { "server_label": "docs" })
    }
    _ => fail("Expected builtin trace preservation")
  }
}
