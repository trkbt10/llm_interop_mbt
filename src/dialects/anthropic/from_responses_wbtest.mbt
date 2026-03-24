///|
/// Whitebox coverage for Responses API -> Anthropic conversion

///|
test "responses_request_to_anthropic covers defaults, instructions, tools, and tool_choice" {
  let request : Json = {
    "model": "claude-sonnet-4-6",
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
      assert_eq(model, "claude-sonnet-4-6")
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
        Object(tool_obj) => {
          match Json::object(tool_obj) {
            { "type": String(type_), "flag": True, .. } =>
              assert_eq(type_, "builtin_alpha")
            _ => fail("Expected builtin tool conversion")
          }
          assert_false(tool_obj.contains("name"))
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
    @utils.extract_responses_tool_name({ "name": "custom_name" }),
    "custom_name",
  )
  assert_eq(@utils.extract_responses_tool_name(Json::null()), "")

  match
    @utils.extract_responses_tool_config({
      "type": "builtin_beta",
      "name": "builtin_beta",
      "description": "ignore",
      "parameters": { "type": "object" },
      "extra": 1,
    }) {
    { "extra": Number(extra, ..), .. } => assert_eq(extra.to_int(), 1)
    _ => fail("Expected filtered config object")
  }
  match @utils.extract_responses_tool_config(Json::null()) {
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

  match
    responses_request_to_anthropic_stream({ "model": "claude-sonnet-4-6" }) {
    { "stream": True, .. } => ()
    _ => fail("Expected streaming Anthropic request")
  }

  match
    responses_request_to_anthropic({
      "model": "claude-sonnet-4-6",
      "tool_choice": "none",
    }) {
    Object(obj) => assert_false(obj.contains("tool_choice"))
    _ => fail("Expected Anthropic request object")
  }
}

///|
test "responses structured output config maps to Anthropics format" {
  let result = responses_request_to_anthropic({
    "model": "claude-sonnet-4-6",
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

///|
test "panic responses_request_to_anthropic rejects missing model" {
  responses_request_to_anthropic({
    "input": [{ "role": "user", "content": "hi" }],
  })
  |> ignore
}

///|
test "panic responses_request_to_anthropic rejects unsupported tool items" {
  responses_request_to_anthropic({
    "model": "claude-sonnet-4-6",
    "tools": [Json::number(1.0)],
  })
  |> ignore
}
