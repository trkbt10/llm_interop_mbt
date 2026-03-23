///|
/// Whitebox coverage for Anthropic -> Responses JSON conversion helpers

///|
test "response_to_responses covers model fallback and error fallbacks" {
  match
    response_to_responses(
      { "content": Json::array([]) },
      response_id="resp_unknown",
    ) {
    { "id": String(id), "model": String(model), "output": Array(output), .. } => {
      assert_eq(id, "resp_unknown")
      assert_eq(model, "unknown")
      assert_eq(output.length(), 0)
    }
    _ => fail("Expected successful fallback response")
  }

  match
    response_to_responses(
      { "error": { "message": "upstream failed" } },
      response_id="resp_error",
    ) {
    { "error": { "type": String(type_), "message": String(message), .. }, .. } => {
      assert_eq(type_, "error")
      assert_eq(message, "upstream failed")
    }
    _ => fail("Expected error response")
  }

  match response_to_responses({ "unexpected": true }, response_id="resp_bad") {
    { "error": { "message": String(message), .. }, .. } =>
      assert_eq(message, "Unknown response format")
    _ => fail("Expected unknown-format fallback")
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
              assert_eq(text, "Code execution output:\n42")
            _ => fail("Expected stdout-only code result text")
          }
          match content[1] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Code execution [stderr]:\nwarn")
            _ => fail("Expected stderr-only code result text")
          }
          match content[2] {
            { "type": String("output_text"), "text": String(text), .. } =>
              assert_eq(text, "Code execution completed (no output)")
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
              assert_eq(text, "Code execution output:\n42\n[stderr]\nwarn")
            _ => fail("Expected combined stdout/stderr text")
          }
          match content[1] {
            { "text": String(text), .. } =>
              assert_eq(text, "Code execution [stderr]:\nonly stderr")
            _ => fail("Expected stderr-only text")
          }
          match content[2] {
            { "text": String(text), .. } =>
              assert_eq(text, "Code execution completed (no output)")
            _ => fail("Expected empty-output fallback")
          }
          match content[3] {
            { "text": String(text), .. } =>
              assert_eq(text, "Code execution output:\nprint(1)")
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
    },
    response_id="resp_alt_code",
  )
  match converted {
    { "output": Array(output), .. } =>
      match output[0] {
        { "type": String("message"), "content": Array(content), .. } =>
          match content[0] {
            { "text": String(text), .. } =>
              assert_eq(text, "Code execution output:\na\n[stderr]\nb")
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
    },
    response_id="resp_tools",
  )

  match converted {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 3)
      match output[0] {
        {
          "type": String("function_call"),
          "name": String(name),
          "arguments": String(arguments),
          ..
        } => {
          assert_eq(name, "lookup")
          assert_true(arguments.contains("\"moonbit\""))
        }
        _ => fail("Expected function_call item")
      }
      match output[1] {
        {
          "type": String("web_search_call"),
          "action": { "type": String("search"), .. },
          ..
        } => ()
        _ => fail("Expected tool_use web_search_call")
      }
      match output[2] {
        {
          "type": String("web_search_call"),
          "action": { "type": String("search"), .. },
          ..
        } => ()
        _ => fail("Expected server_tool_use web_search_call")
      }
    }
    _ => fail("Expected converted tool outputs")
  }
}

///|
test "to_responses wrapper helpers delegate to parser and direct conversion" {
  let response : Json = {
    "model": "claude-sonnet-4-20250514",
    "content": Json::array([{ "type": "text", "text": "Hello" }]),
    "stop_reason": "end_turn",
  }
  match parse_anthropic_as_model_response(response) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected Text from parser wrapper")
  }
  match anthropic_to_responses_full(response, response_id="resp_full") {
    { "id": String(id), "output": Array(output), .. } => {
      assert_eq(id, "resp_full")
      assert_eq(output.length(), 1)
    }
    _ => fail("Expected direct conversion from full wrapper")
  }
}
