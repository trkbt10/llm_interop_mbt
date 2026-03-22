///|
/// Anthropic dialect protocol tests

// Test fixtures
let test_model_anthropic : String = "claude-3-opus-20240229"

// =============================================================================
// Message Conversion Tests (Anthropic Format)
// =============================================================================

///|
test "message_to_json converts System message" {
  let msg = @types.ModelMessage::System("You are Claude")
  let json = message_to_json(msg)
  match json {
    { "role": "system", "content": "You are Claude", .. } => ()
    _ => fail("Unexpected JSON format")
  }
}

///|
test "message_to_json converts Assistant with tool_use" {
  let calls = [
    @types.ToolCallRequest::new(id="toolu_123", name="search", arguments={
      "query": "MoonBit",
    }),
  ]
  let msg = @types.ModelMessage::Assistant(content="", tool_calls=Some(calls))
  let json = message_to_json(msg)
  match json {
    { "role": "assistant", "content": Array(content), .. } => {
      inspect(content.length(), content="1")
      match content[0] {
        { "type": "tool_use", "id": "toolu_123", "name": "search", .. } => ()
        _ => fail("Unexpected tool_use format")
      }
    }
    _ => fail("Unexpected JSON format")
  }
}

// =============================================================================
// Tool Conversion Tests (Anthropic Format)
// =============================================================================

///|
test "tool_to_json creates correct format" {
  let tool = @types.ToolDefinition::new(
    name="calculator",
    description="Calculate math",
    parameters={ "type": "object", "properties": {} },
  )
  let json = tool_to_json(tool)
  match json {
    {
      "name": "calculator",
      "description": "Calculate math",
      "input_schema": _,
      ..
    } => ()
    _ => fail("Unexpected JSON format")
  }
}

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
test "message_to_json converts User with document content_parts" {
  let msg = @types.ModelMessage::User(
    content="Summarize this PDF",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Summarize this PDF"),
      @types.ContentPart::Document(
        data="base64pdf",
        media_type="application/pdf",
        title=Some("report.pdf"),
      ),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } => {
      inspect(parts.length(), content="2")
      match parts[0] {
        { "type": "text", "text": "Summarize this PDF", .. } => ()
        _ => fail("Expected text part")
      }
      match parts[1] {
        { "type": "document", "source": { "type": "base64", .. }, .. } => ()
        _ => fail("Expected document part")
      }
    }
    _ => fail("Expected array content")
  }
}

///|
test "message_to_json converts User with file reference" {
  let msg = @types.ModelMessage::User(
    content="Read this file",
    name=None,
    content_parts=Some([
      @types.ContentPart::Text("Read this file"),
      @types.ContentPart::FileRef(
        file_id="file_abc123",
        media_type=Some("application/pdf"),
      ),
    ]),
  )
  let json = message_to_json(msg)
  match json {
    { "role": "user", "content": Array(parts), .. } =>
      match parts[1] {
        {
          "type": "document",
          "source": { "type": "file", "file_id": "file_abc123", .. },
          ..
        } => ()
        _ => fail("Expected document with file source")
      }
    _ => fail("Expected array content")
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
