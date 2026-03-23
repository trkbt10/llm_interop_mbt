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
test "response_to_chat canonicalizes fenced Gemini structured output" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"text":"```json\n{\"lookup_verification_url_response\":{\"content\":\"{\\\"url\\\":\\\"https://example.com/interop-check\\\"}\"}}\n```"}],"role":"model"},"finishReason":"STOP"}]}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "{\"url\":\"https://example.com/interop-check\"}")
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

///|
test "chat_request_to_gemini: mixed assistant text and tool_calls" {
  let body =
    #|{"model":"gpt-4o-mini","messages":[{"role":"assistant","content":"Checking...","tool_calls":[{"id":"call_01","type":"function","function":{"name":"search","arguments":"{\"q\":\"test\"}"}}]}],"max_tokens":99}
  let result = chat_request_to_gemini(body, {
    max_tokens: 2048,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "contents": [
        {
          "role": String("model"),
          "parts": [
            { "text": String(text), .. },
            {
              "functionCall": {
                "name": String(name),
                "args": { "q": String(query), .. },
                ..
              },
              ..
            },
          ],
          ..
        },
      ],
      "generationConfig": { "maxOutputTokens": Number(max_tokens, ..), .. },
      ..
    } => {
      assert_eq(text, "Checking...")
      assert_eq(name, "search")
      assert_eq(query, "test")
      assert_eq(max_tokens.to_int(), 99)
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "request_to_chat: joins parts and maps generation config" {
  let body =
    #|{"contents":[{"role":"user","parts":[{"text":"Hello"},{"text":"there"}]},{"role":"model","parts":[{"text":"General Kenobi"}]}],"generationConfig":{"maxOutputTokens":128,"temperature":0.4,"topP":0.9,"topK":22,"stopSequences":["END"],"responseMimeType":"application/json","responseJsonSchema":{"type":"object"}}}
  let result = request_to_chat(body, "gpt-4.1", {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "model": String(model),
      "max_completion_tokens": Number(max_tokens, ..),
      "temperature": Number(temp, ..),
      "top_p": Number(top_p, ..),
      "response_format": {
        "type": "json_schema",
        "json_schema": { "schema": { "type": "object", .. }, .. },
        ..
      },
      "messages": [
        { "role": String("user"), "content": String(user_text), .. },
        { "role": String("assistant"), "content": String(model_text), .. },
      ],
      ..
    } => {
      assert_eq(model, "gpt-4.1")
      assert_eq(max_tokens.to_int(), 128)
      assert_eq(temp, 0.4)
      assert_eq(top_p, 0.9)
      assert_eq(user_text, "Hello\nthere")
      assert_eq(model_text, "General Kenobi")
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "chat_request_to_gemini maps OpenAI response_format to generationConfig" {
  let body =
    #|{"messages":[{"role":"user","content":"Return JSON"}],"response_format":{"type":"json_schema","json_schema":{"name":"answer","schema":{"type":"object"},"strict":true}}}
  let result = chat_request_to_gemini(body, {
    max_tokens: 0,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "generationConfig": {
        "responseMimeType": "application/json",
        "responseJsonSchema": { "type": "object", .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected mapped Gemini structured output")
  }
}

///|
test "chat_request_to_gemini lifts system messages into systemInstruction" {
  let body =
    #|{"messages":[{"role":"system","content":"Be exact"},{"role":"user","content":"Return JSON"}]}
  let result = chat_request_to_gemini(body, {
    max_tokens: 0,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "systemInstruction": { "parts": Array(parts), .. },
      "contents": Array(contents),
      ..
    } => {
      assert_eq(contents.length(), 1)
      match parts[0] {
        { "text": String(text), .. } => assert_eq(text, "Be exact")
        _ => fail("Expected systemInstruction text part")
      }
    }
    _ => fail("Expected Gemini systemInstruction")
  }
}
