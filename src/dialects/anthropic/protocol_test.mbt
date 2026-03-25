///|
/// Anthropic dialect protocol tests

// Test fixtures
let test_model_anthropic : String = "claude-3-opus-20240229"

// =============================================================================
// Message Conversion Tests (Anthropic Format)
// =============================================================================

// =============================================================================
// Request Body Builder Tests (Anthropic Format)
// =============================================================================

///|
test "build_body creates valid body" {
  let messages = [
    @types.ModelMessage::System("You are Claude"),
    @types.ModelMessage::User(content="Hello", name=None, content_parts=None),
  ]
  let tools : Array[@types.ToolDefinition] = []
  let body = build_body(
    test_model_anthropic,
    messages,
    tools,
    max_tokens=Some(4096),
  )
  match body {
    {
      "model": String(model),
      "max_tokens": Number(mt, ..),
      "messages": Array(msgs),
      "system": String(sys),
      ..
    } => {
      assert_eq(model, test_model_anthropic)
      inspect(mt, content="4096")
      inspect(msgs.length(), content="1") // System excluded from messages
      inspect(sys, content="You are Claude")
    }
    _ => fail("Unexpected body format")
  }
}

// =============================================================================
// Response Parser Tests (Anthropic Format)
// =============================================================================

///|
test "parse_response parses text response" {
  let json : Json = {
    "content": Json::array([{ "type": "text", "text": "Hello from Claude!" }]),
    "stop_reason": "end_turn",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello from Claude!")
    _ => fail("Expected Text response")
  }
}

///|
test "parse_response preserves Anthropic text citations" {
  let json : Json = {
    "content": Json::array([
      {
        "type": "text",
        "text": "Berkshire Hathaway",
        "citations": Json::array([
          {
            "type": "page_location",
            "cited_text": "Berkshire Hathaway",
            "document_index": 0,
            "document_title": "Annual Report",
            "file_id": "file_annual",
            "start_page_number": 12,
            "end_page_number": 12,
          },
        ]),
      },
    ]),
    "stop_reason": "end_turn",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Berkshire Hathaway")
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::DocumentPageCitation(
          document_title~,
          file_id~,
          start_page_number~,
          end_page_number~,
          start_index~,
          end_index~,
          ..
        ) => {
          assert_eq(document_title, "Annual Report")
          assert_eq(file_id, "file_annual")
          assert_eq(start_page_number, 12)
          assert_eq(end_page_number, 12)
          assert_eq(start_index, 0)
          assert_eq(end_index, "Berkshire Hathaway".length())
        }
        _ => fail("Expected page citation annotation")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_response parses tool_use response" {
  let json : Json = {
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_abc",
        "name": "search",
        "input": { "query": "MoonBit" },
      },
    ]),
    "stop_reason": "tool_use",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="search")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse_response preserves mixed text and tool_use" {
  let json : Json = {
    "content": Json::array([
      { "type": "text", "text": "Let me check that." },
      {
        "type": "tool_use",
        "id": "toolu_abc",
        "name": "search",
        "input": { "query": "MoonBit" },
      },
    ]),
    "stop_reason": "tool_use",
  }
  let response = parse_response(json)
  match response {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "search")
      assert_eq(rich.content, "Let me check that.")
    }
    _ => fail("Expected ToolCallsWithContent response")
  }
}

///|
test "parse_response captures thinking blocks" {
  let response : Json = {
    "content": Json::array([
      { "type": "thinking", "thinking": "Let me analyze this step by step..." },
      { "type": "text", "text": "The answer is 42." },
    ]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="The answer is 42.")
      match rich.content_parts {
        Some(parts) => {
          inspect(parts.length(), content="2")
          match parts[0] {
            @types.ResponseContentPart::Thinking(text~) =>
              inspect(text, content="Let me analyze this step by step...")
            _ => fail("Expected Thinking part")
          }
          match parts[1] {
            @types.ResponseContentPart::OutputText(t) =>
              inspect(t, content="The answer is 42.")
            _ => fail("Expected OutputText part")
          }
        }
        None => fail("Expected content_parts")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_response captures server web search traces" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "server_tool_use",
        "id": "srvtoolu_01SEARCH",
        "name": "web_search",
        "input": { "query": "MoonBit 2026" },
      },
      {
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_01SEARCH",
        "content": Json::array([]),
      },
      { "type": "text", "text": "Here are the results." },
    ]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="Here are the results.")
      inspect(rich.tool_traces.length(), content="1")
      assert_eq(rich.tool_traces[0].kind, @types.ToolCallKind::WebSearch)
      assert_true(
        rich.tool_traces[0].statuses.contains(@types.ToolCallStatus::Completed),
      )
      match rich.tool_traces[0].arguments {
        { "query": "MoonBit 2026", .. } => ()
        _ => fail("Expected preserved web search query")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "parse_response maps tool_use web_search to web-search tool calls" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "tool_use",
        "id": "toolu_01SEARCH",
        "name": "web_search",
        "input": { "query": "MoonBit 2026" },
      },
    ]),
    "stop_reason": "tool_use",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::ToolCalls(tool_calls) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].kind, @types.ToolCallKind::WebSearch)
      match tool_calls[0].arguments {
        { "query": "MoonBit 2026", .. } => ()
        _ => fail("Expected web search query arguments")
      }
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "parse_response captures server code execution request and result" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "server_tool_use",
        "id": "srvtoolu_01CODE",
        "name": "code_execution",
        "input": { "code": "print(42)", "language": "python" },
      },
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "srvtoolu_01CODE",
        "content": { "stdout": "42", "stderr": "", "return_code": 0 },
      },
    ]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          inspect(parts.length(), content="2")
          match parts[0] {
            @types.ResponseContentPart::CodeExecution(language~, code~) => {
              assert_eq(language, "python")
              assert_eq(code, "print(42)")
            }
            _ => fail("Expected CodeExecution part")
          }
          match parts[1] {
            @types.ResponseContentPart::CodeResult(outcome~, output~) => {
              assert_eq(outcome, "success")
              assert_true(output.contains("42"))
            }
            _ => fail("Expected CodeResult part")
          }
        }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "parse_response text-only returns Text not RichText" {
  let response : Json = {
    "content": Json::array([{ "type": "text", "text": "Simple answer" }]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Simple answer")
    _ => fail("Expected plain Text response")
  }
}

///|
test "parse_response captures code_execution_tool_result with stderr" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "toolu_123",
        "content": {
          "stdout": "",
          "stderr": "NameError: name 'foo' is not defined",
          "return_code": 1,
        },
      },
      { "type": "text", "text": "The code failed." },
    ]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          match parts[0] {
            @types.ResponseContentPart::CodeResult(outcome~, output~) => {
              inspect(outcome, content="failed")
              assert_true(output.contains("stderr"))
              assert_true(output.contains("NameError"))
            }
            _ => fail("Expected CodeResult")
          }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "parse_response captures code_execution with both stdout and stderr" {
  let response : Json = {
    "content": Json::array([
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "toolu_456",
        "content": {
          "stdout": "42",
          "stderr": "DeprecationWarning: ...",
          "return_code": 0,
        },
      },
    ]),
    "stop_reason": "end_turn",
  }
  let result = parse_response(response)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          match parts[0] {
            @types.ResponseContentPart::CodeResult(outcome~, output~) => {
              inspect(outcome, content="success")
              assert_true(output.contains("42"))
              assert_true(output.contains("stderr"))
              assert_true(output.contains("DeprecationWarning"))
            }
            _ => fail("Expected CodeResult")
          }
        None => fail("Expected content_parts")
      }
    _ => fail("Expected RichText")
  }
}
