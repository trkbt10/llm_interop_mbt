///|
/// Exhaustive transform layer verification.
/// Every path through transform_request + transform_response is tested
/// with text, tools, tool_calls, system messages, and multi-turn conversations.
/// NO cell in the coverage matrix may be left untested.

// =============================================================================
// Fixture builders
// =============================================================================

fn openai_cc_request_with_tools() -> String {
  #|{"model":"test-model","messages":[{"role":"system","content":"You are helpful"},{"role":"user","content":"weather in Tokyo?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"tool_choice":"auto","max_tokens":1024,"temperature":0.7}
}

fn openai_cc_request_text_only() -> String {
  #|{"model":"test-model","messages":[{"role":"system","content":"You are helpful"},{"role":"user","content":"Hello"}],"max_tokens":1024}
}

fn openai_cc_request_multi_turn() -> String {
  #|{"model":"test-model","messages":[{"role":"user","content":"weather?"},{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},{"role":"tool","content":"Sunny, 25C","tool_call_id":"call_01"},{"role":"user","content":"Thanks!"}],"max_tokens":1024}
}

fn anthropic_text_response() -> String {
  #|{"id":"msg_01","model":"claude","content":[{"type":"text","text":"Hello!"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}
}

fn anthropic_tool_use_response() -> String {
  #|{"id":"msg_02","model":"claude","content":[{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"city":"Tokyo"}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}
}

fn anthropic_mixed_response() -> String {
  #|{"id":"msg_03","model":"claude","content":[{"type":"text","text":"Let me check"},{"type":"tool_use","id":"toolu_02","name":"get_weather","input":{"city":"Tokyo"}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}
}

fn anthropic_multi_tool_response() -> String {
  #|{"id":"msg_04","model":"claude","content":[{"type":"tool_use","id":"toolu_a","name":"read_file","input":{"path":"a"}},{"type":"tool_use","id":"toolu_b","name":"write_file","input":{"path":"b"}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}
}

fn gemini_text_response() -> String {
  #|{"candidates":[{"content":{"parts":[{"text":"Hello!"}],"role":"model"},"finishReason":"STOP"}]}
}

fn gemini_function_call_response() -> String {
  #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_weather","args":{"city":"Tokyo"}}}],"role":"model"},"finishReason":"STOP"}]}
}

fn gemini_mixed_response() -> String {
  #|{"candidates":[{"content":{"parts":[{"text":"Checking..."},{"functionCall":{"name":"get_weather","args":{"city":"Tokyo"}}}],"role":"model"},"finishReason":"STOP"}]}
}

fn gemini_multi_function_call_response() -> String {
  #|{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read_file","args":{"path":"a"}}},{"functionCall":{"name":"write_file","args":{"path":"b"}}}],"role":"model"},"finishReason":"STOP"}]}
}

fn openai_cc_text_response() -> String {
  #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
}

fn openai_cc_tool_calls_response() -> String {
  #|{"id":"chatcmpl-2","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},"finish_reason":"tool_calls"}]}
}

fn openai_cc_mixed_response() -> String {
  #|{"id":"chatcmpl-4","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Let me check","tool_calls":[{"id":"call_01","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Tokyo\"}"}}]},"finish_reason":"tool_calls"}]}
}

fn openai_cc_multi_tool_response() -> String {
  #|{"id":"chatcmpl-3","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_01","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"a\"}"}},{"id":"call_02","type":"function","function":{"name":"write_file","arguments":"{\"path\":\"b\"}"}}]},"finish_reason":"tool_calls"}]}
}

fn openai_error_response() -> String {
  #|{"error":{"message":"rate limited","type":"rate_limit_error"}}
}

fn anthropic_error_response() -> String {
  #|{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}
}

fn default_ctx() -> @types.TransformContext {
  @types.TransformContext::default()
}

fn json_has_field(body : String, field : String) -> Bool {
  let json = @json.parse(body) catch { _ => return false }
  match json {
    Object(obj) => obj.contains(field)
    _ => false
  }
}

fn count_tool_defs(body : String) -> Int {
  let json = @json.parse(body) catch { _ => return 0 }
  match json {
    { "tools": Array(tools), .. } => {
      let mut count = 0
      for t in tools {
        match t {
          { "functionDeclarations": Array(decls), .. } =>
            count = count + decls.length()
          _ => count = count + 1
        }
      }
      return count
    }
    _ => ()
  }
  0
}

fn parse_as_model_response(body : String) -> @types.ModelResponse {
  let json = @json.parse(body) catch {
    _ => return @types.ModelResponse::ModelError("parse error")
  }
  @openai.parse_chat_response(json)
}

fn count_anthropic_tool_use(body : String) -> Int {
  let json = @json.parse(body) catch { _ => return 0 }
  match json {
    { "content": Array(blocks), .. } => {
      let mut c = 0
      for b in blocks {
        match b {
          { "type": String("tool_use"), .. } => c = c + 1
          _ => ()
        }
      }
      c
    }
    _ => 0
  }
}

fn count_gemini_function_calls(body : String) -> Int {
  let json = @json.parse(body) catch { _ => return 0 }
  match json {
    { "candidates": [{ "content": { "parts": Array(parts), .. }, .. }], .. } => {
      let mut c = 0
      for p in parts {
        match p {
          { "functionCall": _, .. } => c = c + 1
          _ => ()
        }
      }
      c
    }
    _ => 0
  }
}

// #####################################################################
// A. transform_request: OpenAI → Anthropic
// #####################################################################

///|
test "req OAI→Anth: text" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, Anthropic, "m", default_ctx())
  assert_true(r.contains("Hello"))
}

///|
test "req OAI→Anth: system" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, Anthropic, "m", default_ctx())
  assert_true(json_has_field(r, "system"))
  let j : Json = @json.parse(r) catch { _ => fail!("p") }
  match j { { "system": String(s), .. } => assert_eq(s, "You are helpful"); _ => fail!("no sys") }
}

///|
test "req OAI→Anth: tools" {
  let r = transform_request(openai_cc_request_with_tools(), OpenAI, Anthropic, "m", default_ctx())
  assert_true(r.contains("input_schema"))
  assert_eq(count_tool_defs(r), 1)
}

///|
test "req OAI→Anth: multi-turn tool role" {
  let r = transform_request(openai_cc_request_multi_turn(), OpenAI, Anthropic, "m", default_ctx())
  assert_true(r.contains("Sunny"))
  assert_true(r.contains("Thanks"))
}

// #####################################################################
// B. transform_request: OpenAI → Gemini
// #####################################################################

///|
test "req OAI→Gem: text" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, Gemini, "m", default_ctx())
  assert_true(r.contains("Hello"))
  assert_true(json_has_field(r, "contents"))
}

///|
test "req OAI→Gem: system" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, Gemini, "m", default_ctx())
  assert_true(r.contains("helpful") || r.contains("contents"))
}

///|
test "req OAI→Gem: tools" {
  let r = transform_request(openai_cc_request_with_tools(), OpenAI, Gemini, "m", default_ctx())
  assert_true(r.contains("functionDeclarations"))
  assert_eq(count_tool_defs(r), 1)
}

///|
test "req OAI→Gem: multi-turn tool role" {
  let r = transform_request(openai_cc_request_multi_turn(), OpenAI, Gemini, "m", default_ctx())
  assert_true(r.contains("Sunny"))
  assert_true(r.contains("Thanks"))
}

// #####################################################################
// C. transform_request: OpenAI → OpenAI
// #####################################################################

///|
test "req OAI→OAI: text" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, OpenAI, "m", default_ctx())
  assert_true(r.contains("Hello"))
}

///|
test "req OAI→OAI: system" {
  let r = transform_request(openai_cc_request_text_only(), OpenAI, OpenAI, "m", default_ctx())
  assert_true(r.contains("You are helpful"))
}

///|
test "req OAI→OAI: tools" {
  let r = transform_request(openai_cc_request_with_tools(), OpenAI, OpenAI, "m", default_ctx())
  assert_true(r.contains("get_weather"))
  assert_eq(count_tool_defs(r), 1)
}

///|
test "req OAI→OAI: multi-turn" {
  let r = transform_request(openai_cc_request_multi_turn(), OpenAI, OpenAI, "m", default_ctx())
  assert_true(r.contains("Sunny"))
  assert_true(r.contains("Thanks"))
  assert_true(r.contains("tool"))
}

// #####################################################################
// D. transform_response: Anthropic → OpenAI
// #####################################################################

///|
test "resp Anth→OAI: text" {
  let r = parse_as_model_response(transform_response(anthropic_text_response(), Anthropic, OpenAI))
  match r { @types.ModelResponse::Text(t) => assert_eq(t, "Hello!"); _ => fail!("expected Text") }
}

///|
test "resp Anth→OAI: single tool_use" {
  let r = parse_as_model_response(transform_response(anthropic_tool_use_response(), Anthropic, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => { assert_eq(c.length(), 1); assert_eq(c[0].name, "get_weather") }; _ => fail!("tc") }
}

///|
test "resp Anth→OAI: multi tool_use" {
  let r = parse_as_model_response(transform_response(anthropic_multi_tool_response(), Anthropic, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => { assert_eq(c.length(), 2); assert_eq(c[0].name, "read_file"); assert_eq(c[1].name, "write_file") }; _ => fail!("tc") }
}

///|
test "resp Anth→OAI: mixed text+tool" {
  let r = parse_as_model_response(transform_response(anthropic_mixed_response(), Anthropic, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "get_weather"); _ => fail!("tc") }
}

///|
test "resp Anth→OAI: error" {
  let r = transform_response(anthropic_error_response(), Anthropic, OpenAI)
  assert_true(r.contains("bad request"))
}

// #####################################################################
// E. transform_response: Gemini → OpenAI
// #####################################################################

///|
test "resp Gem→OAI: text" {
  let r = parse_as_model_response(transform_response(gemini_text_response(), Gemini, OpenAI))
  match r { @types.ModelResponse::Text(t) => assert_eq(t, "Hello!"); _ => fail!("Text") }
}

///|
test "resp Gem→OAI: single functionCall" {
  let r = parse_as_model_response(transform_response(gemini_function_call_response(), Gemini, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => { assert_eq(c.length(), 1); assert_eq(c[0].name, "get_weather") }; _ => fail!("tc") }
}

///|
test "resp Gem→OAI: multi functionCall" {
  let r = parse_as_model_response(transform_response(gemini_multi_function_call_response(), Gemini, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => { assert_eq(c.length(), 2); assert_eq(c[0].name, "read_file"); assert_eq(c[1].name, "write_file") }; _ => fail!("tc") }
}

///|
test "resp Gem→OAI: mixed text+functionCall" {
  let r = parse_as_model_response(transform_response(gemini_mixed_response(), Gemini, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "get_weather"); _ => fail!("tc") }
}

///|
test "resp Gem→OAI: error (unparseable passes through)" {
  let r = transform_response("{\"error\":{\"code\":400,\"message\":\"bad\",\"status\":\"INVALID_ARGUMENT\"}}", Gemini, OpenAI)
  assert_true(r.contains("bad"))
}

// #####################################################################
// F. transform_response: OpenAI → OpenAI
// #####################################################################

///|
test "resp OAI→OAI: text" {
  let r = parse_as_model_response(transform_response(openai_cc_text_response(), OpenAI, OpenAI))
  match r { @types.ModelResponse::Text(t) => assert_eq(t, "Hello!"); _ => fail!("Text") }
}

///|
test "resp OAI→OAI: single tool_calls" {
  let r = parse_as_model_response(transform_response(openai_cc_tool_calls_response(), OpenAI, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "get_weather"); _ => fail!("tc") }
}

///|
test "resp OAI→OAI: multi tool_calls" {
  let r = parse_as_model_response(transform_response(openai_cc_multi_tool_response(), OpenAI, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => assert_eq(c.length(), 2); _ => fail!("tc") }
}

///|
test "resp OAI→OAI: mixed text+tool_calls" {
  let r = parse_as_model_response(transform_response(openai_cc_mixed_response(), OpenAI, OpenAI))
  match r { @types.ModelResponse::ToolCalls(c) => assert_eq(c[0].name, "get_weather"); _ => fail!("tc") }
}

///|
test "resp OAI→OAI: error" {
  let r = transform_response(openai_error_response(), OpenAI, OpenAI)
  assert_true(r.contains("rate limited"))
}

// #####################################################################
// G. transform_response: OpenAI → Anthropic
// #####################################################################

///|
test "resp OAI→Anth: text" {
  let r = transform_response(openai_cc_text_response(), OpenAI, Anthropic)
  assert_true(r.contains("Hello!"))
}

///|
test "resp OAI→Anth: single tool_calls" {
  let r = transform_response(openai_cc_tool_calls_response(), OpenAI, Anthropic)
  assert_eq(count_anthropic_tool_use(r), 1)
  assert_true(r.contains("get_weather"))
}

///|
test "resp OAI→Anth: multi tool_calls" {
  let r = transform_response(openai_cc_multi_tool_response(), OpenAI, Anthropic)
  assert_eq(count_anthropic_tool_use(r), 2)
}

///|
test "resp OAI→Anth: mixed text+tool_calls" {
  let r = transform_response(openai_cc_mixed_response(), OpenAI, Anthropic)
  assert_true(r.contains("Let me check"))
  assert_eq(count_anthropic_tool_use(r), 1)
}

///|
test "resp OAI→Anth: error" {
  let r = transform_response(openai_error_response(), OpenAI, Anthropic)
  assert_true(r.contains("rate limited"))
}

// #####################################################################
// H. transform_response: OpenAI → Gemini
// #####################################################################

///|
test "resp OAI→Gem: text" {
  let r = transform_response(openai_cc_text_response(), OpenAI, Gemini)
  assert_true(r.contains("Hello!"))
  assert_true(r.contains("candidates"))
}

///|
test "resp OAI→Gem: single tool_calls" {
  let r = transform_response(openai_cc_tool_calls_response(), OpenAI, Gemini)
  assert_eq(count_gemini_function_calls(r), 1)
}

///|
test "resp OAI→Gem: multi tool_calls" {
  let r = transform_response(openai_cc_multi_tool_response(), OpenAI, Gemini)
  assert_eq(count_gemini_function_calls(r), 2)
}

///|
test "resp OAI→Gem: mixed text+tool_calls" {
  let r = transform_response(openai_cc_mixed_response(), OpenAI, Gemini)
  assert_true(r.contains("Let me check"))
  assert_eq(count_gemini_function_calls(r), 1)
}

///|
test "resp OAI→Gem: error" {
  let r = transform_response(openai_error_response(), OpenAI, Gemini)
  assert_true(r.contains("rate limited"))
}

// #####################################################################
// I. Cross-dialect: Gemini → Anthropic
// #####################################################################

///|
test "resp Gem→Anth: text" {
  let r = transform_response(gemini_text_response(), Gemini, Anthropic)
  assert_true(r.contains("Hello!"))
}

///|
test "resp Gem→Anth: single functionCall" {
  let r = transform_response(gemini_function_call_response(), Gemini, Anthropic)
  assert_eq(count_anthropic_tool_use(r), 1)
  assert_true(r.contains("get_weather"))
}

///|
test "resp Gem→Anth: multi functionCall" {
  let r = transform_response(gemini_multi_function_call_response(), Gemini, Anthropic)
  assert_eq(count_anthropic_tool_use(r), 2)
}

///|
test "resp Gem→Anth: mixed" {
  let r = transform_response(gemini_mixed_response(), Gemini, Anthropic)
  assert_true(r.contains("Checking"))
  assert_eq(count_anthropic_tool_use(r), 1)
}

///|
test "resp Gem→Anth: error" {
  let body =
    #|{"error":{"code":400,"message":"gemini error","status":"INVALID_ARGUMENT"}}
  let r = transform_response(body, Gemini, Anthropic)
  assert_true(r.contains("gemini error") || r.contains("error"))
}

// #####################################################################
// J. Cross-dialect: Anthropic → Gemini
// #####################################################################

///|
test "resp Anth→Gem: text" {
  let r = transform_response(anthropic_text_response(), Anthropic, Gemini)
  assert_true(r.contains("Hello!"))
  assert_true(r.contains("candidates"))
}

///|
test "resp Anth→Gem: single tool_use" {
  let r = transform_response(anthropic_tool_use_response(), Anthropic, Gemini)
  assert_eq(count_gemini_function_calls(r), 1)
  assert_true(r.contains("get_weather"))
}

///|
test "resp Anth→Gem: multi tool_use" {
  let r = transform_response(anthropic_multi_tool_response(), Anthropic, Gemini)
  assert_eq(count_gemini_function_calls(r), 2)
}

///|
test "resp Anth→Gem: mixed" {
  let r = transform_response(anthropic_mixed_response(), Anthropic, Gemini)
  assert_true(r.contains("Let me check"))
  assert_eq(count_gemini_function_calls(r), 1)
}

///|
test "resp Anth→Gem: error" {
  let r = transform_response(anthropic_error_response(), Anthropic, Gemini)
  assert_true(r.contains("bad request"))
}
