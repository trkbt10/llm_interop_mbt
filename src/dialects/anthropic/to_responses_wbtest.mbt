///|
/// Whitebox coverage for Anthropic -> Responses JSON conversion helpers

///|
test "response_to_responses covers error fallbacks" {
  match
    response_to_responses(
      { "error": { "message": "upstream failed" } },
      response_id="resp_error",
    ) {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "api_error")
      assert_eq(message, "upstream failed")
    }
    _ => fail("Expected error response")
  }

  match response_to_responses({ "unexpected": true }, response_id="resp_bad") {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "parse_error")
      assert_eq(message, "Unknown response format")
    }
    _ => fail("Expected unknown-format fallback")
  }
}

///|
test "response_to_responses serializes malformed payloads as structured failures" {
  match
    response_to_responses(
      { "content": Json::array([]) },
      response_id="resp_unknown",
    ) {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "parse_error")
      assert_eq(message, "Unknown response format")
    }
    _ => fail("Expected structured malformed-payload failure")
  }
}

///|
test "response_to_responses preserves reasoning and code execution text variants" {
  let converted = response_to_responses(
    {
      "model": "claude-sonnet-4-20250514",
      "content": Json::array([
        { "type": "thinking", "thinking": "Plan first" },
        { "type": "redacted_thinking", "data": "enc_blob" },
        { "type": "code_execution_tool_result", "content": { "stdout": "42" } },
        {
          "type": "bash_code_execution_tool_result",
          "content": { "stderr": "warn" },
        },
        { "type": "text_editor_code_execution_tool_result", "content": {} },
        { "type": "text", "text": "Done." },
      ]),
      "stop_reason": "end_turn",
    },
    response_id="resp_reasoning",
  )

  match converted {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 3)
      match output[0] {
        { "type": String("reasoning"), "summary": Array(summary), .. } =>
          match summary[0] {
            { "text": String(text), .. } => assert_eq(text, "Plan first")
            _ => fail("Expected reasoning summary text")
          }
        _ => fail("Expected first reasoning item")
      }
      match output[1] {
        {
          "type": String("reasoning"),
          "summary": Array(summary),
          "encrypted_content": String(encrypted),
          ..
        } => {
          assert_eq(summary.length(), 0)
          assert_eq(encrypted, "enc_blob")
        }
        _ => fail("Expected encrypted reasoning item")
      }
      match output[2] {
        { "type": String("message"), "content": Array(content), .. } => {
          assert_eq(content.length(), 4)
          match content[0] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Execution [success]: 42")
            _ => fail("Expected stdout-only code result text")
          }
          match content[1] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Execution [failed]: [stderr]\nwarn")
            _ => fail("Expected stderr-only code result text")
          }
          match content[2] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(
                text, "Execution [success]: Code execution completed (no output)",
              )
            _ => fail("Expected empty code result fallback text")
          }
          match content[3] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Done.")
            _ => fail("Expected plain text part")
          }
        }
        _ => fail("Expected message output item")
      }
    }
    _ => fail("Expected converted output array")
  }
}

///|
test "response_to_responses covers remaining code execution branches and ignores unknown blocks" {
  let converted = response_to_responses(
    {
      "model": "claude-sonnet-4-20250514",
      "content": Json::array([
        {
          "type": "code_execution_tool_result",
          "content": { "stdout": "42", "stderr": "warn" },
        },
        {
          "type": "code_execution_tool_result",
          "content": { "stderr": "only stderr" },
        },
        { "type": "code_execution_tool_result", "content": {} },
        {
          "type": "bash_code_execution_tool_result",
          "content": { "stdout": "print(1)" },
        },
        { "type": "unsupported_block", "payload": true },
      ]),
      "stop_reason": "end_turn",
    },
    response_id="resp_code_paths",
  )

  match converted {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 1)
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } => {
          assert_eq(content.length(), 4)
          match content[0] {
            { "text": String(text), .. } =>
              assert_eq(text, "Execution [failed]: 42\n[stderr]\nwarn")
            _ => fail("Expected combined stdout/stderr text")
          }
          match content[1] {
            { "text": String(text), .. } =>
              assert_eq(text, "Execution [failed]: [stderr]\nonly stderr")
            _ => fail("Expected stderr-only text")
          }
          match content[2] {
            { "text": String(text), .. } =>
              assert_eq(
                text, "Execution [success]: Code execution completed (no output)",
              )
            _ => fail("Expected empty-output fallback")
          }
          match content[3] {
            { "text": String(text), .. } =>
              assert_eq(text, "Execution [success]: print(1)")
            _ => fail("Expected stdout-only alternate tool text")
          }
        }
        _ => fail("Expected single message item")
      }
    }
    _ => fail("Expected converted output array")
  }
}

///|
test "response_to_responses covers combined output for alternate code execution blocks" {
  let converted = response_to_responses(
    {
      "model": "claude-sonnet-4-20250514",
      "content": Json::array([
        {
          "type": "bash_code_execution_tool_result",
          "content": { "stdout": "a", "stderr": "b" },
        },
      ]),
      "stop_reason": "end_turn",
    },
    response_id="resp_alt_code",
  )
  match converted {
    { "output": Array(output), .. } =>
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "text": String(text), .. } =>
              assert_eq(text, "Execution [failed]: a\n[stderr]\nb")
            _ => fail("Expected combined alternate code execution text")
          }
        _ => fail("Expected message output item")
      }
    _ => fail("Expected converted output")
  }
}

///|
test "response_to_responses converts tool_use and server web search blocks" {
  let converted = response_to_responses(
    {
      "model": "claude-sonnet-4-20250514",
      "content": Json::array([
        {
          "type": "tool_use",
          "id": "toolu_fn",
          "name": "lookup",
          "input": { "q": "moonbit" },
        },
        {
          "type": "tool_use",
          "id": "toolu_web",
          "name": @types.web_search_tool_name(),
          "input": { "query": "coverage" },
        },
        {
          "type": "server_tool_use",
          "id": "srvtoolu_web",
          "name": @types.web_search_tool_name(),
          "input": { "query": "docs" },
        },
        {
          "type": "server_tool_use",
          "id": "srvtoolu_code",
          "name": "code_execution",
          "input": { "code": "print(1)" },
        },
      ]),
      "stop_reason": "tool_use",
    },
    response_id="resp_tools",
  )

  match converted {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 4)
      let mut saw_function_call = false
      let mut web_search_calls = 0
      let mut saw_code_execution_input = false
      for item in output {
        match item {
          {
            "type": String("function_call"),
            "name": String(name),
            "arguments": String(arguments),
            ..
          } => {
            assert_eq(name, "lookup")
            assert_true(arguments.contains("\"moonbit\""))
            saw_function_call = true
          }
          {
            "type": String("web_search_call"),
            "action": { "type": String("search"), .. },
            ..
          } => web_search_calls = web_search_calls + 1
          { "type": String("message"), "content": Array(content), .. } =>
            match content[0] {
              { "text": String(text), .. } => {
                assert_eq(text, "```python\nprint(1)\n```")
                saw_code_execution_input = true
              }
              _ => fail("Expected code execution prompt text")
            }
          _ => fail("Unexpected output item in mixed tool conversion")
        }
      }
      assert_true(saw_function_call)
      assert_eq(web_search_calls, 2)
      assert_true(saw_code_execution_input)
    }
    _ => fail("Expected converted tool outputs")
  }
}

///|
test "response_to_responses preserves Anthropic text citations via canonical path" {
  let converted = response_to_responses(
    {
      "model": "claude-sonnet-4-20250514",
      "content": Json::array([
        {
          "type": "text",
          "text": "Weather details",
          "citations": Json::array([
            {
              "type": "web_search_result_location",
              "cited_text": "Weather details",
              "encrypted_index": "enc_tokyo",
              "title": "Tokyo Weather",
              "url": "https://example.com/tokyo",
            },
          ]),
        },
      ]),
      "stop_reason": "end_turn",
    },
    response_id="resp_citation",
  )

  match converted {
    {
      "id": String(id),
      "output": [
        {
          "type": String("message"),
          "content": [
            {
              "type": String("output_text"),
              "text": String(text),
              "annotations": Array(annotations),
              ..
            },
          ],
          ..
        },
      ],
      ..
    } => {
      assert_eq(id, "resp_citation")
      assert_eq(text, "Weather details")
      assert_eq(annotations.length(), 1)
      match annotations[0] {
        {
          "type": String("web_search_result_location"),
          "title": String(title),
          "start_index": Number(start_index, ..),
          "end_index": Number(end_index, ..),
          ..
        } => {
          assert_eq(title, "Tokyo Weather")
          assert_eq(start_index.to_int(), 0)
          assert_eq(end_index.to_int(), 15)
        }
        _ => fail("Expected preserved citation annotation")
      }
    }
    _ => fail("Expected Responses output with preserved annotations")
  }
}

///|
test "to_responses canonical entrypoints cover parser and direct conversion" {
  let response : Json = {
    "model": "claude-sonnet-4-20250514",
    "content": Json::array([{ "type": "text", "text": "Hello" }]),
    "stop_reason": "end_turn",
  }
  match parse_response(response) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected Text from parser")
  }
  match response_to_responses(response, response_id="resp_full") {
    { "id": String(id), "output": Array(output), .. } => {
      assert_eq(id, "resp_full")
      assert_eq(output.length(), 1)
    }
    _ => fail("Expected direct conversion from canonical entrypoint")
  }
}
