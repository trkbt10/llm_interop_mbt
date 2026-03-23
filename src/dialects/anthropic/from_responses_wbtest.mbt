///|
/// Whitebox coverage for Responses API -> Anthropic conversion

///|
test "responses_request_to_anthropic covers defaults, instructions, tools, and tool_choice" {
  let request : Json = {
    "instructions": "Be concise",
    "input": Json::array([
      {
        "role": "user",
        "content": Json::array([{ "type": "input_text", "text": "Hi" }]),
      },
    ]),
    "tools": Json::array([
      { "type": "function", "name": "lookup" },
      { "type": "builtin_alpha", "description": "kept in config", "flag": true },
      Json::number(1.0),
    ]),
    "tool_choice": { "type": "function", "name": "lookup" },
  }
  let result = responses_request_to_anthropic(request)
  match result {
    {
      "model": String(model),
      "messages": Array(messages),
      "max_tokens": Number(max_tokens, ..),
      "system": String(system),
      "tools": Array(tools),
      "tool_choice": {
        "type": String(choice_type),
        "name": String(choice_name),
        ..
      },
      ..
    } => {
      assert_eq(model, "")
      assert_eq(messages.length(), 1)
      assert_eq(max_tokens.to_int(), 8192)
      assert_eq(system, "Be concise")
      assert_eq(choice_type, "tool")
      assert_eq(choice_name, "lookup")

      match tools[0] {
        {
          "name": String(name),
          "description": String(description),
          "input_schema": Object(schema),
          ..
        } => {
          assert_eq(name, "lookup")
          assert_eq(description, "")
          assert_eq(schema.length(), 0)
        }
        _ => fail("Expected function tool conversion")
      }

      match tools[1] {
        { "type": String(type_), "name": String(name), "flag": True, .. } => {
          assert_eq(type_, "builtin_alpha")
          assert_eq(name, "builtin_alpha")
        }
        _ => fail("Expected builtin tool conversion")
      }
    }
    _ => fail("Expected Anthropic request body")
  }
}

///|
test "from_responses helpers cover config extraction and stream flag" {
  assert_eq(
    extract_tool_name({ "name": "custom_name" }, "fallback"),
    "custom_name",
  )
  assert_eq(extract_tool_name(Json::null(), "fallback"), "fallback")

  match
    extract_tool_config({
      "type": "builtin_beta",
      "name": "builtin_beta",
      "description": "ignore",
      "parameters": { "type": "object" },
      "extra": 1,
    }) {
    { "extra": Number(extra, ..), .. } => assert_eq(extra.to_int(), 1)
    _ => fail("Expected filtered config object")
  }
  match extract_tool_config(Json::null()) {
    Object(obj) => assert_eq(obj.length(), 0)
    _ => fail("Expected empty config object")
  }

  assert_eq(convert_tool_choice_to_anthropic("auto"), Some({ "type": "auto" }))
  assert_eq(convert_tool_choice_to_anthropic("none"), None)
  assert_eq(
    convert_tool_choice_to_anthropic("required"),
    Some({ "type": "any" }),
  )
  assert_eq(
    convert_tool_choice_to_anthropic({ "type": "function", "name": "search" }),
    Some({ "type": "tool", "name": "search" }),
  )
  assert_eq(
    convert_tool_choice_to_anthropic({
      "type": "function",
      "function": { "name": "search" },
    }),
    Some({ "type": "tool", "name": "search" }),
  )
  assert_eq(convert_tool_choice_to_anthropic({ "type": "unknown" }), None)

  match responses_request_to_anthropic_stream({}) {
    { "stream": True, .. } => ()
    _ => fail("Expected streaming Anthropic request")
  }

  match responses_request_to_anthropic({ "tool_choice": "none" }) {
    Object(obj) => assert_false(obj.contains("tool_choice"))
    _ => fail("Expected Anthropic request object")
  }
}

///|
test "responses structured output config maps to Anthropics format" {
  let result = responses_request_to_anthropic({
    "input": [{ "role": "user", "content": "Return JSON" }],
    "text": { "format": { "type": "json_object" } },
  })
  match result {
    {
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": { "type": "object", "additionalProperties": False, .. },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Anthropics structured output format")
  }
}
