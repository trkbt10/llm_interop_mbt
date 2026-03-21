///|
/// Transform tests using REAL API response fixtures.
/// These fixtures were captured from actual API calls:
///   - OpenAI gpt-4o-mini (2025-03-21)
///   - Groq llama-3.3-70b / gpt-oss-20b (2025-03-02)
///   - Anthropic claude-sonnet-4 (2025-03-02)
///   - Gemini gemini-2.0-flash (2025-03-02)
///
/// Each test loads a real fixture, runs it through the transform pipeline,
/// and verifies the output is correctly parseable as ModelResponse.

fn load(path : String) -> String {
  @utils.read_testdata(path) catch {
    e => {
      ignore(e)
      ""
    }
  }
}

// #####################################################################
// OpenAI CC fixtures (real gpt-4o-mini responses)
// #####################################################################

///|
test "fixture/openai-cc/text: parse directly" {
  let body = load("testdata/openai/chat_completions/live_text_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(_) => ()
    _ => fail!("expected Text from real OpenAI text fixture")
  }
}

///|
test "fixture/openai-cc/toolcall: parse directly" {
  let body = load("testdata/openai/chat_completions/live_toolcall_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_true(calls.length() > 0)
      assert_true(calls[0].name.length() > 0)
    }
    _ => fail!("expected ToolCalls from real OpenAI toolcall fixture")
  }
}

///|
test "fixture/openai-cc/toolcall: transform OpenAI→OpenAI preserves" {
  let body = load("testdata/openai/chat_completions/live_toolcall_20250321.json")
  let transformed = transform_response(body, OpenAI, OpenAI)
  let json : Json = @json.parse(transformed) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => assert_true(calls.length() > 0)
    _ => fail!("expected ToolCalls after identity transform")
  }
}

// #####################################################################
// Groq fixtures (real llama-3.3/gpt-oss responses, OpenAI CC format)
// #####################################################################

///|
test "fixture/groq/text: parse as OpenAI CC" {
  let body = load("testdata/groq/chat_completions/text_nonstream.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(_) => ()
    _ => fail!("expected Text from real Groq text fixture")
  }
}

///|
test "fixture/groq/toolcall: parse as OpenAI CC" {
  let body = load("testdata/groq/chat_completions/toolcall_nonstream.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_true(calls.length() > 0)
      // Groq tool call should have name "get_weather"
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail!("expected ToolCalls from real Groq toolcall fixture")
  }
}

///|
test "fixture/groq/toolcall: transform OpenAI→OpenAI preserves" {
  let body = load("testdata/groq/chat_completions/toolcall_nonstream.json")
  let transformed = transform_response(body, OpenAI, OpenAI)
  let json : Json = @json.parse(transformed) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => assert_eq(calls[0].name, "get_weather")
    _ => fail!("expected ToolCalls after identity transform of Groq fixture")
  }
}

// #####################################################################
// Anthropic fixtures (real claude-sonnet-4 responses)
// #####################################################################

///|
test "fixture/anthropic/text: transform Anthropic→OpenAI and parse" {
  let body = load("testdata/anthropic/messages/text_nonstream.json")
  let openai = transform_response(body, Anthropic, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(t) => {
      // Real fixture says "Four"
      assert_true(t.length() > 0)
    }
    _ => fail!("expected Text from real Anthropic text fixture → OpenAI transform")
  }
}

///|
test "fixture/anthropic/toolcall: transform Anthropic→OpenAI and parse" {
  let body = load("testdata/anthropic/messages/toolcall_nonstream.json")
  let openai = transform_response(body, Anthropic, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_true(calls.length() > 0)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail!("expected ToolCalls from real Anthropic toolcall fixture → OpenAI transform")
  }
}

///|
test "fixture/anthropic/toolcall: real fixture has mixed text+tool_use" {
  // The real Anthropic fixture has BOTH text and tool_use in content
  let body = load("testdata/anthropic/messages/toolcall_nonstream.json")
  assert_true(body.length() > 0)
  // Verify the fixture actually has text AND tool_use (compact JSON, no spaces in keys)
  assert_true(body.contains("tool_use"))
  assert_true(body.contains("\"text\""))
  // Transform should produce ToolCalls (tool_use takes precedence)
  let openai = transform_response(body, Anthropic, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls[0].name, "get_weather")
      // Real fixture has toolu_ ID, converted to call_ for OpenAI CC
      assert_true(calls[0].id.has_prefix("call_"))
    }
    _ => fail!("expected ToolCalls from mixed Anthropic fixture")
  }
}

// #####################################################################
// Gemini fixtures (real gemini-2.0-flash responses)
// #####################################################################

///|
test "fixture/gemini/text: transform Gemini→OpenAI and parse" {
  let body = load("testdata/gemini/generate_content/text_nonstream.json")
  let openai = transform_response(body, Gemini, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(t) => assert_true(t.contains("Hello"))
    _ => fail!("expected Text from real Gemini text fixture → OpenAI transform")
  }
}

///|
test "fixture/gemini/toolcall: transform Gemini→OpenAI and parse" {
  let body = load("testdata/gemini/generate_content/toolcall_nonstream.json")
  let openai = transform_response(body, Gemini, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail!("expected ToolCalls from real Gemini toolcall fixture → OpenAI transform")
  }
}

///|
test "fixture/gemini/multi_toolcall: transform Gemini→OpenAI and parse" {
  let body = load("testdata/gemini/generate_content/multi_toolcall_nonstream.json")
  let openai = transform_response(body, Gemini, OpenAI)
  let json : Json = @json.parse(openai) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].name, "get_weather")
      assert_eq(calls[1].name, "get_time")
    }
    _ => fail!("expected ToolCalls with 2 calls from real Gemini multi-tool fixture")
  }
}

// #####################################################################
// Cross-dialect: real fixtures through pivot transforms
// #####################################################################

///|
test "fixture/anthropic→gemini: real toolcall fixture" {
  let body = load("testdata/anthropic/messages/toolcall_nonstream.json")
  let gemini = transform_response(body, Anthropic, Gemini)
  // Should have functionCall
  assert_true(gemini.contains("functionCall"))
  assert_true(gemini.contains("get_weather"))
}

///|
test "fixture/gemini→anthropic: real toolcall fixture" {
  let body = load("testdata/gemini/generate_content/toolcall_nonstream.json")
  let anthropic = transform_response(body, Gemini, Anthropic)
  // Should have tool_use
  assert_true(anthropic.contains("tool_use"))
  assert_true(anthropic.contains("get_weather"))
}

///|
test "fixture/groq→anthropic: real toolcall fixture (OpenAI CC → Anthropic)" {
  let body = load("testdata/groq/chat_completions/toolcall_nonstream.json")
  let anthropic = transform_response(body, OpenAI, Anthropic)
  assert_true(anthropic.contains("tool_use"))
  assert_true(anthropic.contains("get_weather"))
}

///|
test "fixture/groq→gemini: real toolcall fixture (OpenAI CC → Gemini)" {
  let body = load("testdata/groq/chat_completions/toolcall_nonstream.json")
  let gemini = transform_response(body, OpenAI, Gemini)
  assert_true(gemini.contains("functionCall"))
  assert_true(gemini.contains("get_weather"))
}

// #####################################################################
// New real fixtures from 2025-03-21 API calls
// #####################################################################

///|
test "fixture/live-openai-text: real gpt-4o-mini text response" {
  let body = load("testdata/openai/chat_completions/live_text_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(t) => assert_eq(t, "Hello!")
    _ => fail!("expected Text")
  }
}

///|
test "fixture/live-openai-toolcall: real gpt-4o-mini tool_calls response" {
  let body = load("testdata/openai/chat_completions/live_toolcall_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "get_weather")
      // Real response has a real call ID
      assert_true(calls[0].id.has_prefix("call_"))
    }
    _ => fail!("expected ToolCalls")
  }
}

///|
test "fixture/live-groq-text: real llama-3.3-70b text response" {
  let body = load("testdata/groq/chat_completions/live_text_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::Text(t) => assert_eq(t, "hello")
    _ => fail!("expected Text")
  }
}

///|
test "fixture/live-groq-toolcall: real llama-3.3-70b tool_calls response" {
  let body = load("testdata/groq/chat_completions/live_toolcall_20250321.json")
  let json : Json = @json.parse(body) catch { _ => fail!("parse") }
  let resp = @openai.parse_chat_response(json)
  match resp {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail!("expected ToolCalls from live Groq fixture")
  }
}
