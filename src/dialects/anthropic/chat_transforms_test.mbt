///|
/// Tests for Anthropic ↔ OpenAI Chat Completions transforms

///|
test "response_to_chat: text response" {
  let body =
    #|{"id":"msg_01","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Hello world"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "content": String(content), .. }, "finish_reason": String(fr), .. }], .. } => {
      assert_eq(content, "Hello world")
      assert_eq(fr, "stop")
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: tool_use response" {
  let body =
    #|{"id":"msg_02","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"location":"Tokyo"}}],"stop_reason":"tool_use"}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "choices": [{
        "message": { "tool_calls": Array(tcs), "content": Null, .. },
        "finish_reason": String(fr),
        ..
      }],
      ..
    } => {
      assert_eq(fr, "tool_calls")
      assert_eq(tcs.length(), 1)
      match tcs[0] {
        { "id": String(id), "type": String(typ), "function": { "name": String(name), "arguments": String(args), .. }, .. } => {
          assert_eq(id, "call_01") // toolu_01 → call_01 via interop ID conversion
          assert_eq(typ, "function")
          assert_eq(name, "get_weather")
          assert_true(args.contains("Tokyo"))
        }
        _ => fail("unexpected tool_call structure")
      }
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: mixed text and tool_use" {
  let body =
    #|{"id":"msg_03","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Let me check"},{"type":"tool_use","id":"toolu_02","name":"search","input":{"q":"test"}}],"stop_reason":"tool_use"}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "choices": [{
        "message": { "content": String(content), "tool_calls": Array(tcs), .. },
        "finish_reason": String(fr),
        ..
      }],
      ..
    } => {
      assert_eq(content, "Let me check")
      assert_eq(fr, "tool_calls")
      assert_eq(tcs.length(), 1)
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: multiple tool_use blocks" {
  let body =
    #|{"id":"msg_04","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","id":"toolu_a","name":"read_file","input":{"path":"/tmp/a"}},{"type":"tool_use","id":"toolu_b","name":"read_file","input":{"path":"/tmp/b"}}],"stop_reason":"tool_use"}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "tool_calls": Array(tcs), .. }, .. }], .. } =>
      assert_eq(tcs.length(), 2)
    _ => fail("unexpected structure: \{result}")
  }
}
