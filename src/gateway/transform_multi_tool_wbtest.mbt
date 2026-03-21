///|
/// Exhaustive multi-tool transform tests using REAL API response fixtures.

fn load_fixture(path : String) -> String {
  @utils.read_testdata(path) catch { _ => "" }
}

fn parse_oai(body : String) -> @types.ModelResponse {
  let json = @json.parse(body) catch { _ => return @types.ModelResponse::ModelError("parse") }
  @openai.parse_chat_response(json)
}

fn xform_and_parse(body : String, from : GatewaySurface) -> @types.ModelResponse {
  parse_oai(transform_response(body, from, OpenAI))
}

// #####################################################################
// A. Direct parse: each fixture → ModelResponse
// #####################################################################

///|
test "multi/parse/openai: 2 tools" {
  let r = parse_oai(load_fixture("testdata/openai/chat_completions/live_multi_toolcall_20250321.json"))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
      assert_true(c[0].id.has_prefix("call_"))
      assert_true(c[0].id != c[1].id)
      assert_true(c[0].arguments.stringify().contains("Tokyo"))
      assert_true(c[1].arguments.stringify().contains("config.json"))
    }
    _ => fail("expected 2 ToolCalls from OpenAI")
  }
}

///|
test "multi/parse/groq: 2 tools" {
  let r = parse_oai(load_fixture("testdata/groq/chat_completions/live_multi_toolcall_20250321.json"))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
      assert_true(c[0].id != c[1].id)
    }
    _ => fail("expected 2 ToolCalls from Groq")
  }
}

///|
test "multi/parse/gemini: 2 tools (via transform)" {
  let r = xform_and_parse(load_fixture("testdata/gemini/generate_content/multi_toolcall_nonstream.json"), Gemini)
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "get_time")
      assert_true(c[0].id != c[1].id)
    }
    _ => fail("expected 2 ToolCalls from Gemini")
  }
}

///|
test "multi/parse/anthropic: 1 tool mixed with text (via transform)" {
  let r = xform_and_parse(load_fixture("testdata/anthropic/messages/toolcall_nonstream.json"), Anthropic)
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 1)
      assert_eq(c[0].name, "get_weather")
      assert_true(c[0].id.has_prefix("call_")) // toolu_ → call_ via interop
    }
    _ => fail("expected ToolCalls from Anthropic")
  }
}

// #####################################################################
// B. OpenAI multi-tool → every target → back → verify
// #####################################################################

///|
test "multi/rt/openai→anthropic→openai" {
  let body = load_fixture("testdata/openai/chat_completions/live_multi_toolcall_20250321.json")
  let anth = transform_response(body, OpenAI, Anthropic)
  // Verify Anthropic intermediate
  let anth_json : Json = @json.parse(anth) catch { _ => fail("parse anth") }
  match anth_json {
    { "content": Array(blocks), "stop_reason": String(sr), .. } => {
      assert_eq(sr, "tool_use")
      let mut tu = 0
      for b in blocks { match b { { "type": String("tool_use"), .. } => tu = tu + 1; _ => () } }
      assert_eq(tu, 2)
    }
    _ => fail("bad anthropic")
  }
  // Round-trip back
  let r = parse_oai(transform_response(anth, Anthropic, OpenAI))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
      assert_true(c[0].arguments.stringify().contains("Tokyo"))
      assert_true(c[1].arguments.stringify().contains("config.json"))
    }
    _ => fail("roundtrip failed")
  }
}

///|
test "multi/rt/openai→gemini→openai" {
  let body = load_fixture("testdata/openai/chat_completions/live_multi_toolcall_20250321.json")
  let gem = transform_response(body, OpenAI, Gemini)
  let gem_json : Json = @json.parse(gem) catch { _ => fail("parse gem") }
  match gem_json {
    { "candidates": [{ "content": { "parts": Array(parts), .. }, .. }], .. } => {
      let mut fc = 0
      for p in parts { match p { { "functionCall": _, .. } => fc = fc + 1; _ => () } }
      assert_eq(fc, 2)
    }
    _ => fail("bad gemini")
  }
  let r = parse_oai(transform_response(gem, Gemini, OpenAI))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
    }
    _ => fail("roundtrip failed")
  }
}

///|
test "multi/rt/groq→anthropic→openai" {
  let body = load_fixture("testdata/groq/chat_completions/live_multi_toolcall_20250321.json")
  let anth = transform_response(body, OpenAI, Anthropic)
  let r = parse_oai(transform_response(anth, Anthropic, OpenAI))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
    }
    _ => fail("roundtrip failed")
  }
}

///|
test "multi/rt/groq→gemini→openai" {
  let body = load_fixture("testdata/groq/chat_completions/live_multi_toolcall_20250321.json")
  let gem = transform_response(body, OpenAI, Gemini)
  let r = parse_oai(transform_response(gem, Gemini, OpenAI))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 2)
      assert_eq(c[0].name, "get_weather")
      assert_eq(c[1].name, "read_file")
    }
    _ => fail("roundtrip failed")
  }
}

// #####################################################################
// C. Gemini multi-tool → every target → back → verify
// #####################################################################

///|
test "multi/rt/gemini→openai→gemini" {
  let body = load_fixture("testdata/gemini/generate_content/multi_toolcall_nonstream.json")
  let oai = transform_response(body, Gemini, OpenAI)
  let back = transform_response(oai, OpenAI, Gemini)
  let json : Json = @json.parse(back) catch { _ => fail("parse") }
  match json {
    { "candidates": [{ "content": { "parts": Array(parts), .. }, .. }], .. } => {
      let names : Array[String] = []
      for p in parts {
        match p { { "functionCall": { "name": String(n), .. }, .. } => names.push(n); _ => () }
      }
      assert_eq(names.length(), 2)
      assert_eq(names[0], "get_weather")
      assert_eq(names[1], "get_time")
    }
    _ => fail("bad gemini roundtrip")
  }
}

///|
test "multi/rt/gemini→anthropic→gemini" {
  let body = load_fixture("testdata/gemini/generate_content/multi_toolcall_nonstream.json")
  let anth = transform_response(body, Gemini, Anthropic)
  let anth_json : Json = @json.parse(anth) catch { _ => fail("parse anth") }
  match anth_json {
    { "content": Array(blocks), .. } => {
      let mut tu = 0
      for b in blocks { match b { { "type": String("tool_use"), .. } => tu = tu + 1; _ => () } }
      assert_eq(tu, 2)
    }
    _ => fail("bad anthropic")
  }
  let back = transform_response(anth, Anthropic, Gemini)
  let json : Json = @json.parse(back) catch { _ => fail("parse") }
  match json {
    { "candidates": [{ "content": { "parts": Array(parts), .. }, .. }], .. } => {
      let mut fc = 0
      for p in parts { match p { { "functionCall": _, .. } => fc = fc + 1; _ => () } }
      assert_eq(fc, 2)
    }
    _ => fail("bad gemini after anthropic roundtrip")
  }
}

// #####################################################################
// D. Anthropic mixed → cross-dialect → verify tool survives
// #####################################################################

///|
test "multi/cross/anthropic→gemini preserves tool" {
  let body = load_fixture("testdata/anthropic/messages/toolcall_nonstream.json")
  let gem = transform_response(body, Anthropic, Gemini)
  let json : Json = @json.parse(gem) catch { _ => fail("parse") }
  match json {
    { "candidates": [{ "content": { "parts": Array(parts), .. }, .. }], .. } => {
      let mut fc = 0
      for p in parts { match p { { "functionCall": _, .. } => fc = fc + 1; _ => () } }
      assert_eq(fc, 1) // one tool_use in the Anthropic fixture
    }
    _ => fail("bad gemini from anthropic")
  }
}

///|
test "multi/cross/anthropic→gemini→openai preserves tool" {
  let body = load_fixture("testdata/anthropic/messages/toolcall_nonstream.json")
  let gem = transform_response(body, Anthropic, Gemini)
  let r = parse_oai(transform_response(gem, Gemini, OpenAI))
  match r {
    @types.ModelResponse::ToolCalls(c) => {
      assert_eq(c.length(), 1)
      assert_eq(c[0].name, "get_weather")
    }
    _ => fail("tool lost in triple transform")
  }
}
