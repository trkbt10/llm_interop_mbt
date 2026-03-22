///|
/// Tests for Gemini ↔ OpenAI Chat Completions transforms

///|
test "response_to_chat: text response" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"text":"Hello world"}],"role":"model"},"finishReason":"STOP"}]}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "choices": [
        {
          "message": { "content": String(content), .. },
          "finish_reason": String(fr),
          ..
        },
      ],
      ..
    } => {
      assert_eq(content, "Hello world")
      assert_eq(fr, "stop")
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: functionCall response" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_weather","args":{"location":"Tokyo"}}}],"role":"model"},"finishReason":"STOP"}]}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "choices": [
        {
          "message": { "tool_calls": Array(tcs), "content": Null, .. },
          "finish_reason": String(fr),
          ..
        },
      ],
      ..
    } => {
      assert_eq(fr, "tool_calls")
      assert_eq(tcs.length(), 1)
      match tcs[0] {
        {
          "id": String(id),
          "type": String(typ),
          "function": { "name": String(name), "arguments": String(args), .. },
          ..
        } => {
          assert_true(id.has_prefix("call_")) // gemini ID → OpenAI CC format via interop
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
test "response_to_chat: mixed text and functionCall" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"text":"Checking..."},{"functionCall":{"name":"search","args":{"q":"test"}}}],"role":"model"},"finishReason":"STOP"}]}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "choices": [
        {
          "message": {
            "content": String(content),
            "tool_calls": Array(tcs),
            ..
          },
          "finish_reason": String(fr),
          ..
        },
      ],
      ..
    } => {
      assert_eq(content, "Checking...")
      assert_eq(fr, "tool_calls")
      assert_eq(tcs.length(), 1)
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: multiple functionCall parts" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read","args":{"path":"a"}}},{"functionCall":{"name":"write","args":{"path":"b"}}}],"role":"model"},"finishReason":"STOP"}]}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "tool_calls": Array(tcs), .. }, .. }], .. } =>
      assert_eq(tcs.length(), 2)
    _ => fail("unexpected structure: \{result}")
  }
}
