///|
/// Multi-turn tool conversation transform tests.
/// Verifies that assistant tool_calls and tool results survive dialect transforms.

// OpenAI CC multi-turn request with assistant tool_calls + tool result
fn openai_multiturn_request() -> String {
  let s =
    #|{"model":"test","messages":[{"role":"user","content":"weather?"},{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},{"role":"tool","content":"Sunny 25C","tool_call_id":"call_01"},{"role":"user","content":"Thanks!"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}}}}}],"max_tokens":1024}
  s
}

///|
fn openai_first_turn_tool_choice_request() -> String {
  let s =
    #|{"model":"test","messages":[{"role":"system","content":"Call the tool exactly once."},{"role":"user","content":"Look up the verification URL for anth-stream."}],"tools":[{"type":"function","function":{"name":"lookup_verification_url","description":"Return the verification URL for a label","parameters":{"type":"object","properties":{"label":{"type":"string"}},"required":["label"]}}}],"tool_choice":{"type":"function","function":{"name":"lookup_verification_url"}},"stream":true,"max_tokens":128}
  s
}

///|
fn openai_first_turn_gemini_request() -> String {
  let s =
    #|{"model":"test","messages":[{"role":"system","content":"Call the tool exactly once."},{"role":"user","content":"Look up the verification URL for gem-stream."}],"tools":[{"type":"function","function":{"name":"lookup_verification_url","description":"Return the verification URL for a label","parameters":{"type":"object","properties":{"label":{"type":"string"}},"required":["label"]}}}],"tool_choice":{"type":"function","function":{"name":"lookup_verification_url"}},"stream":true,"max_tokens":128}
  s
}

///|
fn default_tc() -> @types.TransformContext {
  @types.TransformContext::default()
}

// =============================================================================
// A. OpenAI → Anthropic: multi-turn tool conversation
// =============================================================================

///|
test "multiturn/req/oai→anth: assistant tool_calls become tool_use content" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Anthropic, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    { "messages": Array(msgs), .. } => {
      // Find the assistant message — it should contain tool_use content
      let mut found_tool_use = false
      for msg in msgs {
        match msg {
          { "role": String("assistant"), "content": Array(blocks), .. } =>
            for block in blocks {
              match block {
                { "type": String("tool_use"), "name": String(n), .. } => {
                  assert_eq(n, "get_weather")
                  found_tool_use = true
                }
                _ => ()
              }
            }
          _ => ()
        }
      }
      assert_true(found_tool_use)
    }
    _ => fail("bad structure")
  }
}

///|
test "multiturn/req/oai→anth: tool result becomes user tool_result" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Anthropic, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    { "messages": Array(msgs), .. } => {
      let mut found_tool_result = false
      for msg in msgs {
        match msg {
          { "role": String("user"), "content": Array(blocks), .. } =>
            for block in blocks {
              match block {
                { "type": String("tool_result"), "tool_use_id": String(id), .. } => {
                  assert_eq(id, "toolu_01") // call_01 → toolu_01 via interop ID conversion
                  found_tool_result = true
                }
                _ => ()
              }
            }
          _ => ()
        }
      }
      assert_true(found_tool_result)
    }
    _ => fail("bad structure")
  }
}

///|
test "multiturn/req/oai→anth: tools definition preserved" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Anthropic, "test", default_tc())
  assert_true(result.contains("input_schema"))
  assert_true(result.contains("get_weather"))
}

///|
test "multiturn/req/oai→anth: all user content preserved" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Anthropic, "test", default_tc())
  assert_true(result.contains("weather?"))
  assert_true(result.contains("Thanks!"))
  assert_true(result.contains("Sunny"))
}

///|
test "multiturn/req/oai→anth: explicit function tool_choice and stream survive first turn" {
  let req = openai_first_turn_tool_choice_request()
  let result = transform_request(req, OpenAI, Anthropic, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    {
      "stream": True,
      "system": String(system),
      "tool_choice": {
        "type": String(choice_type),
        "name": String(choice_name),
        ..
      },
      "messages": [
        { "role": String("user"), "content": String(user_content), .. },
      ],
      ..
    } => {
      assert_eq(system, "Call the tool exactly once.")
      assert_eq(choice_type, "tool")
      assert_eq(choice_name, "lookup_verification_url")
      assert_true(user_content.contains("anth-stream"))
    }
    _ => fail("bad structure")
  }
}

// =============================================================================
// B. OpenAI → Gemini: multi-turn tool conversation
// =============================================================================

///|
test "multiturn/req/oai→gem: assistant tool_calls become functionCall parts" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Gemini, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    { "contents": Array(contents), .. } => {
      let mut found_fc = false
      for c in contents {
        match c {
          { "role": String("model"), "parts": Array(parts), .. } =>
            for p in parts {
              match p {
                { "functionCall": { "name": String(n), .. }, .. } => {
                  assert_eq(n, "get_weather")
                  found_fc = true
                }
                _ => ()
              }
            }
          _ => ()
        }
      }
      assert_true(found_fc)
    }
    _ => fail("bad structure")
  }
}

///|
test "multiturn/req/oai→gem: tool result becomes functionResponse" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Gemini, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    { "contents": Array(contents), .. } => {
      let mut found_fr = false
      for c in contents {
        match c {
          { "parts": Array(parts), .. } =>
            for p in parts {
              match p {
                { "functionResponse": { "name": String(n), .. }, .. } => {
                  assert_eq(n, "get_weather")
                  found_fr = true
                }
                _ => ()
              }
            }
          _ => ()
        }
      }
      assert_true(found_fr)
    }
    _ => fail("bad structure")
  }
}

///|
test "multiturn/req/oai→gem: tools definition preserved as functionDeclarations" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Gemini, "test", default_tc())
  assert_true(result.contains("functionDeclarations"))
  assert_true(result.contains("get_weather"))
}

///|
test "multiturn/req/oai→gem: all user content preserved" {
  let req = openai_multiturn_request()
  let result = transform_request(req, OpenAI, Gemini, "test", default_tc())
  assert_true(result.contains("weather?") || result.contains("weather"))
  assert_true(result.contains("Thanks"))
}

///|
test "multiturn/req/oai→gem: first turn preserves system, tools, and user content" {
  let req = openai_first_turn_gemini_request()
  let result = transform_request(req, OpenAI, Gemini, "test", default_tc())
  let json : Json = @json.parse(result) catch { _ => fail("parse") }
  match json {
    {
      "systemInstruction": { "parts": Array(system_parts), .. },
      "tools": [{ "functionDeclarations": Array(decls), .. }],
      "contents": [{ "role": String("user"), "parts": Array(user_parts), .. }],
      ..
    } => {
      let mut found_system = false
      for part in system_parts {
        match part {
          { "text": String(text), .. } => {
            assert_eq(text, "Call the tool exactly once.")
            found_system = true
          }
          _ => ()
        }
      }
      assert_true(found_system)
      let mut found_decl = false
      for decl in decls {
        match decl {
          { "name": String(name), .. } =>
            if name == "lookup_verification_url" {
              found_decl = true
            }
          _ => ()
        }
      }
      assert_true(found_decl)
      let mut found_user = false
      for part in user_parts {
        match part {
          { "text": String(text), .. } => {
            assert_true(text.contains("gem-stream"))
            found_user = true
          }
          _ => ()
        }
      }
      assert_true(found_user)
    }
    _ => fail("bad structure")
  }
}
