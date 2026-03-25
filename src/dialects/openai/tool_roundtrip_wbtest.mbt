///|
/// Agent loop 典型パターンの Responses API リクエストボディ変換テスト
/// mukuro の agent loop が生成するメッセージ列が正しく変換されることを検証する

///|
test "build_responses_api_body: tool call roundtrip (System → User → Assistant+ToolCalls → ToolResult → User)" {
  // fixture: agent loop の2回目リクエスト相当
  // 1回目で tool call が発生し、結果を含めて2回目の User メッセージを追加
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::System("You are a helpful assistant with tools."),
    @types.ModelMessage::User(
      content="What is today's date?",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(
          id="call_get_date",
          name="get_current_date",
          arguments={},
        ),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_get_date",
      content="2026-03-25",
    ),
  ]
  let tools : Array[@types.ToolDefinition] = [
    @types.ToolDefinition::new(
      name="get_current_date",
      description="Get the current date",
      parameters={ "type": "object", "properties": {} },
    ),
  ]
  let body = build_responses_api_body("gpt-4.1", messages, tools)
  match body {
    { "model": "gpt-4.1", "input": Array(items), "tools": Array(tool_defs), .. } => {
      // input items: System + User + function_call + function_call_output = 4
      assert_eq(items.length(), 4)
      // [0] System
      assert_eq(items[0], { "role": "system", "content": "You are a helpful assistant with tools." })
      // [1] User
      assert_eq(items[1], { "role": "user", "content": "What is today's date?" })
      // [2] function_call (Assistant の tool_calls が展開される)
      match items[2] {
        { "type": "function_call", "name": "get_current_date", .. } => ()
        other => fail("Expected function_call item, got: \{other}")
      }
      // [3] function_call_output (ToolResult)
      match items[3] {
        { "type": "function_call_output", "output": "2026-03-25", .. } => ()
        other => fail("Expected function_call_output item, got: \{other}")
      }
      // tools
      assert_eq(tool_defs.length(), 1)
    }
    _ => fail("Expected valid Responses API body")
  }
}

///|
test "build_responses_api_body: second user message after tool roundtrip" {
  // fixture: agent loop の2リクエスト目
  // セッション履歴に前回の tool call roundtrip が含まれ、新しい User メッセージが追加される
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::System("You are a helpful assistant."),
    // 1st turn
    @types.ModelMessage::User(
      content="What is today's date?",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(
          id="call_date",
          name="get_date",
          arguments={},
        ),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_date",
      content="2026-03-25",
    ),
    @types.ModelMessage::Assistant(
      content="Today is March 25, 2026.",
      tool_calls=None,
    ),
    // 2nd turn
    @types.ModelMessage::User(
      content="What happened today?",
      name=None,
      content_parts=None,
    ),
  ]
  let body = build_responses_api_body("gpt-4.1", messages, [])
  match body {
    { "input": Array(items), .. } => {
      // System + User1 + function_call + function_call_output + Assistant(text) + User2 = 6
      assert_eq(items.length(), 6)
      // 最後が 2nd turn の User メッセージ
      assert_eq(items[5], { "role": "user", "content": "What happened today?" })
      // Assistant(text) は function_call_output の後
      assert_eq(items[4], { "role": "assistant", "content": "Today is March 25, 2026." })
    }
    _ => fail("Expected valid body")
  }
}

///|
test "build_responses_api_body: Assistant with empty content and tool_calls does not emit assistant message" {
  // Agent loop の ToolCalls 分岐: content="" で tool_calls がある場合
  // Responses API では content="" の assistant メッセージは出力されず、
  // function_call items のみが出力されるべき
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(
      content="Search for news",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(
          id="call_search",
          name="web_search",
          arguments={ "query": "today's news" },
        ),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_search",
      content="Breaking news: MoonBit 1.0 released",
    ),
  ]
  let body = build_responses_api_body("gpt-4.1", messages, [])
  match body {
    { "input": Array(items), .. } => {
      // User + function_call + function_call_output = 3
      // Assistant(content="") は出力されない（messages_to_responses_input line 80: content.length() > 0 チェック）
      assert_eq(items.length(), 3)
      assert_eq(items[0], { "role": "user", "content": "Search for news" })
      match items[1] {
        { "type": "function_call", "name": "web_search", .. } => ()
        other => fail("Expected function_call, got: \{other}")
      }
      match items[2] {
        { "type": "function_call_output", "output": String(output), .. } =>
          assert_true(output.contains("MoonBit"))
        other => fail("Expected function_call_output, got: \{other}")
      }
    }
    _ => fail("Expected valid body")
  }
}

///|
test "build_responses_api_body: multiple tool calls in single assistant message" {
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(
      content="What time is it and what's the weather?",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content="",
      tool_calls=Some([
        @types.ToolCallRequest::new(
          id="call_time",
          name="get_time",
          arguments={},
        ),
        @types.ToolCallRequest::new(
          id="call_weather",
          name="get_weather",
          arguments={ "location": "Tokyo" },
        ),
      ]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_time",
      content="19:35 JST",
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id="call_weather",
      content="Sunny, 22°C",
    ),
  ]
  let body = build_responses_api_body("gpt-4.1", messages, [])
  match body {
    { "input": Array(items), .. } => {
      // User + 2 function_calls + 2 function_call_outputs = 5
      assert_eq(items.length(), 5)
      match items[1] {
        { "type": "function_call", "name": "get_time", .. } => ()
        other => fail("Expected get_time call, got: \{other}")
      }
      match items[2] {
        { "type": "function_call", "name": "get_weather", .. } => ()
        other => fail("Expected get_weather call, got: \{other}")
      }
      match items[3] {
        { "type": "function_call_output", "output": "19:35 JST", .. } => ()
        other => fail("Expected time result, got: \{other}")
      }
      match items[4] {
        { "type": "function_call_output", "output": "Sunny, 22°C", .. } => ()
        other => fail("Expected weather result, got: \{other}")
      }
    }
    _ => fail("Expected valid body")
  }
}
