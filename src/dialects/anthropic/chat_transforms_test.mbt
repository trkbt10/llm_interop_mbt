///|
/// Tests for Anthropic ↔ OpenAI Chat Completions transforms

///|
test "response_to_chat: text response" {
  let body =
    #|{"id":"msg_01","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Hello world"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}
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
test "response_to_chat: tool_use response" {
  let body =
    #|{"id":"msg_02","model":"claude-sonnet-4-20250514","content":[{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"location":"Tokyo"}}],"stop_reason":"tool_use"}
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
      assert_eq(content, "Let me check")
      assert_eq(fr, "tool_calls")
      assert_eq(tcs.length(), 1)
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "response_to_chat: web citations down-convert to OpenAI chat annotations" {
  let body =
    #|{"id":"msg_03c","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Weather details","citations":[{"type":"web_search_result_location","cited_text":"Weather details","encrypted_index":"enc_tokyo","title":"Tokyo Weather","url":"https://example.com/tokyo"}]}],"stop_reason":"end_turn"}
  let result = response_to_chat(body)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": message, .. }], .. } =>
      match message {
        Object(fields) => {
          match fields.get("content") {
            Some(String(content)) => assert_eq(content, "Weather details")
            _ => fail("Expected chat text content")
          }
          match fields.get("annotations") {
            Some(Array(annotations)) => {
              assert_eq(annotations.length(), 1)
              match annotations[0] {
                {
                  "type": String("url_citation"),
                  "url_citation": {
                    "title": String(title),
                    "url": String(url),
                    "start_index": Number(start_index, ..),
                    "end_index": Number(end_index, ..),
                    ..
                  },
                  ..
                } => {
                  assert_eq(title, "Tokyo Weather")
                  assert_eq(url, "https://example.com/tokyo")
                  assert_eq(start_index.to_int(), 0)
                  assert_eq(end_index.to_int(), 15)
                }
                _ => fail("Expected OpenAI chat url_citation annotation")
              }
            }
            _ => fail("Expected chat annotations")
          }
        }
        _ => fail("Expected message object")
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

///|
test "chat_request_to_anthropic: mixed assistant text and tool_calls" {
  let body =
    #|{"model":"gpt-4o-mini","messages":[{"role":"assistant","content":"Let me check","tool_calls":[{"id":"call_01","type":"function","function":{"name":"search","arguments":"{\"q\":\"test\"}"}}]}],"tool_choice":{"type":"function","function":{"name":"search"}},"max_completion_tokens":123}
  let result = chat_request_to_anthropic(body, {
    max_tokens: 4096,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "max_tokens": Number(max_tokens, ..),
      "tool_choice": {
        "type": String(choice_type),
        "name": String(choice_name),
        ..
      },
      "messages": [
        {
          "role": String("assistant"),
          "content": [
            { "type": String("text"), "text": String(text), .. },
            {
              "type": String("tool_use"),
              "name": String(name),
              "input": { "q": String(query), .. },
              ..
            },
          ],
          ..
        },
      ],
      ..
    } => {
      assert_eq(max_tokens.to_int(), 123)
      assert_eq(choice_type, "tool")
      assert_eq(choice_name, "search")
      assert_eq(text, "Let me check")
      assert_eq(name, "search")
      assert_eq(query, "test")
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "chat_request_to_anthropic maps OpenAI required tool_choice to any" {
  let result = chat_request_to_anthropic(
    "{\"messages\":[{\"role\":\"user\",\"content\":\"Use a tool\"}],\"tool_choice\":\"required\"}",
    { max_tokens: 256, max_tokens_field: "max_tokens" },
  )
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "tool_choice": { "type": String(choice_type), .. }, .. } =>
      assert_eq(choice_type, "any")
    _ => fail("Expected Anthropic tool_choice")
  }
}

///|
test "request_to_chat: system multimodal content and params" {
  let body =
    #|{"model":"claude-sonnet-4-20250514","system":"Be concise","messages":[{"role":"user","content":[{"type":"text","text":"Look at this"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"abc123"}}]}],"max_tokens":256,"temperature":0.3,"top_p":0.8,"top_k":5,"stop_sequences":["END"],"stream":true,"output_config":{"format":{"type":"json_schema","schema":{"type":"object"}}}}
  let result = request_to_chat(body, {
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
      "response_format": { "type": "json_schema", .. },
      "stop": Array(stop),
      "stream": True,
      "messages": [
        { "role": String("system"), "content": String(system), .. },
        { "role": String("user"), "content": Array(parts), .. },
      ],
      ..
    } => {
      assert_eq(model, "claude-sonnet-4-20250514")
      assert_eq(max_tokens.to_int(), 256)
      assert_eq(temp, 0.3)
      assert_eq(top_p, 0.8)
      assert_eq(stop.length(), 1)
      assert_eq(system, "Be concise")
      match parts[0] {
        { "type": String("text"), "text": String(text), .. } =>
          assert_eq(text, "Look at this")
        _ => fail("Expected text part")
      }
      match parts[1] {
        {
          "type": String("image_url"),
          "image_url": { "url": String(url), .. },
          ..
        } => assert_true(url.has_prefix("data:image/png;base64,abc123"))
        _ => fail("Expected image_url part")
      }
    }
    _ => fail("unexpected structure: \{result}")
  }
}

///|
test "request_to_chat: missing top-level fields and mixed content fallbacks" {
  let minimal = request_to_chat("{}", {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let minimal_json : Json = @json.parse(minimal) catch {
    _ => fail("parse error")
  }
  match minimal_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 0)
    _ => fail("Expected empty messages array")
  }

  let body =
    #|{"messages":[{"role":"user","content":"hello"},{"role":"assistant","content":[{"type":"unknown"},{"type":"text","text":"ok"}]},{"role":"user","content":{"unsupported":true}}]}
  let result = request_to_chat(body, {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "messages": [
        { "content": String(first), .. },
        { "content": Array(second), .. },
        { "content": { "unsupported": True, .. }, .. },
      ],
      ..
    } => {
      assert_eq(first, "hello")
      assert_eq(second.length(), 1)
      match second[0] {
        { "type": String("text"), "text": String(text), .. } =>
          assert_eq(text, "ok")
        _ => fail("Expected retained text block")
      }
    }
    _ => fail("Unexpected fallback transform result")
  }
}

///|
test "chat_request_to_anthropic: skips unsupported entries and pivots multimodal user parts" {
  let missing_fields = chat_request_to_anthropic(
    "{\"tools\":[{\"type\":\"not-function\"}]}",
    { max_tokens: 512, max_tokens_field: "max_tokens" },
  )
  let missing_json : Json = @json.parse(missing_fields) catch {
    _ => fail("parse error")
  }
  match missing_json {
    { "max_tokens": Number(max_tokens, ..), "messages": Array(messages), .. } => {
      assert_eq(max_tokens.to_int(), 512)
      assert_eq(messages.length(), 0)
    }
    _ => fail("Expected default anthropic envelope")
  }

  let body =
    #|{"model":"gpt-4o-mini","messages":[{"role":"assistant","content":"Working","tool_calls":[{"id":"call_bad"}]},{"unexpected":true},{"role":"user","content":[{"type":"text","text":"Look"},{"type":"image_url","image_url":{"url":"data:image/png;base64,abc123"}},{"type":"image_url","image_url":{"url":"https://example.com/not-supported.png"}}]}],"tools":[{"type":"function","function":{"name":"lookup","description":"Lookup docs","parameters":{"type":"object","properties":{}}}},{"type":"not-function"}]}
  let result = chat_request_to_anthropic(body, {
    max_tokens: 256,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "messages": [
        {
          "role": String("assistant"),
          "content": [{ "type": String("text"), "text": String(text), .. }],
          ..
        },
        {
          "role": String("user"),
          "content": [
            { "type": String("text"), "text": String(user_text), .. },
            {
              "type": String("image"),
              "source": {
                "type": String("base64"),
                "media_type": String("image/png"),
                "data": String(data),
                ..
              },
              ..
            },
          ],
          ..
        },
      ],
      "tools": [{ "name": String(tool_name), .. }],
      ..
    } => {
      assert_eq(text, "Working")
      assert_eq(user_text, "Look")
      assert_eq(data, "abc123")
      assert_eq(tool_name, "lookup")
    }
    _ => fail("Unexpected anthropic request result")
  }
}

///|
test "chat_request_to_anthropic maps OpenAI response_format to Anthropic format" {
  let body =
    #|{"messages":[{"role":"user","content":"Return JSON"}],"response_format":{"type":"json_object"}}
  let result = chat_request_to_anthropic(body, {
    max_tokens: 128,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": { "type": "object", .. },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected mapped Anthropic format")
  }
}

///|
test "chat_request_to_anthropic drops OpenAI-only schema metadata but preserves schema body" {
  let body =
    #|{"messages":[{"role":"user","content":"Return structured JSON"}],"response_format":{"type":"json_schema","json_schema":{"name":"answer","description":"Structured answer","schema":{"type":"object","properties":{"url":{"type":"string","format":"uri"}}},"strict":true}}}
  let result = chat_request_to_anthropic(body, {
    max_tokens: 128,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": {
            "properties": {
              "url": { "type": String("string"), "format": String("uri"), .. },
              ..
            },
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Anthropic schema body without OpenAI-only metadata")
  }
}
