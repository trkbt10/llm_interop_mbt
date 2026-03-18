///|
/// Harmony package tests

// Test fixtures
let test_response_id : String = "resp_001"

///|
let test_model : String = "gpt-4"

///|
let test_model_harmony : String = "openai/gpt-oss-20b"

///|
fn read_harmony_fixture(path : String) -> String raise {
  @utils.read_testdata(path)
}

///|
fn translate_harmony_fixture(
  path : String,
  response_id : String,
) -> Array[@sse.SseEvent] raise {
  let content = read_harmony_fixture(path)
  let events = @sse.parse_jsonl(content)
  let translator = HarmonyToResponsesTranslator::new(response_id~)
  let translated : Array[@sse.SseEvent] = []
  for event in events {
    for translated_event in translator.translate(event) {
      translated.push({ event: translated_event.0, data: translated_event.1 })
    }
  }
  translated
}

///|
fn accumulate_translated_responses(
  events : Array[@sse.SseEvent],
) -> @types.ModelResponse {
  let acc = @openai.ResponsesApiAccumulator::new()
  for event in events {
    acc.feed(event)
  }
  acc.finish()
}

// =============================================================================
// Responses API Input -> Messages Tests
// =============================================================================

///|
test "responses_input_to_messages: basic user message" {
  let input : Array[Json] = [
    { "role": "system", "content": "You are helpful." },
    { "role": "user", "content": "Hello" },
  ]
  let messages = responses_input_to_messages(input)
  inspect(messages.length(), content="2")
  match messages[0] {
    @types.ModelMessage::System(content) =>
      inspect(content, content="You are helpful.")
    _ => fail("Expected System message")
  }
  match messages[1] {
    @types.ModelMessage::User(content~, ..) => inspect(content, content="Hello")
    _ => fail("Expected User message")
  }
}

///|
test "responses_input_to_messages: function_call and output" {
  let input : Array[Json] = [
    { "role": "user", "content": "What time is it?" },
    {
      "type": "function_call",
      "call_id": "fc_123",
      "name": "datetime",
      "arguments": "{}",
      "status": "completed",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_123",
      "output": "{\"time\":\"15:00\"}",
    },
  ]
  let messages = responses_input_to_messages(input)
  inspect(messages.length(), content="3")
  // User message
  match messages[0] {
    @types.ModelMessage::User(content~, ..) =>
      inspect(content, content="What time is it?")
    _ => fail("Expected User message")
  }
  // Assistant with tool call
  match messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="fc_123")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected Assistant message with tool_calls")
  }
  // Tool result
  match messages[2] {
    @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
      inspect(tool_call_id, content="fc_123")
      inspect(content, content="{\"time\":\"15:00\"}")
    }
    _ => fail("Expected ToolResult message")
  }
}

///|
test "responses_input_to_messages: web_search_call becomes builtin tool call" {
  let input : Array[Json] = [
    { "role": "user", "content": "Find current weather" },
    {
      "type": "web_search_call",
      "id": "ws_123",
      "status": "completed",
      "action": {
        "type": "search",
        "query": "current weather in Tokyo",
        "queries": Json::array([Json::string("current weather in Tokyo")]),
      },
    },
  ]
  let messages = responses_input_to_messages(input)
  inspect(messages.length(), content="2")
  match messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].kind, @types.ToolCallKind::WebSearch)
      assert_eq(calls[0].name, "web_search")
      match calls[0].arguments {
        { "query": String(query), .. } =>
          assert_eq(query, "current weather in Tokyo")
        _ => fail("Expected query argument")
      }
    }
    _ => fail("Expected Assistant with web search tool call")
  }
}

///|
test "responses_input_to_messages: multiple parallel tool calls" {
  let input : Array[Json] = [
    { "role": "user", "content": "Get time and weather" },
    {
      "type": "function_call",
      "call_id": "fc_time",
      "name": "datetime",
      "arguments": "{}",
    },
    {
      "type": "function_call",
      "call_id": "fc_weather",
      "name": "weather",
      "arguments": "{\"city\":\"Tokyo\"}",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_time",
      "output": "{\"time\":\"15:00\"}",
    },
    {
      "type": "function_call_output",
      "call_id": "fc_weather",
      "output": "{\"temp\":\"20C\"}",
    },
  ]
  let messages = responses_input_to_messages(input)
  // Should be: User, Assistant(2 tool_calls), ToolResult, ToolResult
  inspect(messages.length(), content="4")
  // User
  match messages[0] {
    @types.ModelMessage::User(content~, ..) =>
      inspect(content, content="Get time and weather")
    _ => fail("Expected User")
  }
  // Assistant with 2 tool calls
  match messages[1] {
    @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) => {
      inspect(calls.length(), content="2")
      inspect(calls[0].name, content="datetime")
      inspect(calls[1].name, content="weather")
    }
    _ => fail("Expected Assistant with 2 tool_calls")
  }
}

// =============================================================================
// ModelResponse -> Responses API JSON Tests
// =============================================================================

///|
test "model_response_to_responses_json: text response" {
  let response = @types.ModelResponse::Text("Hello, world!")
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "id": String(id), "output": Array(output), .. } => {
      assert_eq(id, test_response_id)
      inspect(output.length(), content="1")
      match output[0] {
        { "type": String("message"), "content": Array(content_arr), .. } =>
          match content_arr[0] {
            { "type": String("output_text"), "text": String(t), .. } =>
              inspect(t, content="Hello, world!")
            _ => fail("Expected output_text")
          }
        _ => fail("Expected message output")
      }
    }
    _ => fail("Expected valid response JSON")
  }
}

///|
test "model_response_to_responses_json: tool calls" {
  let calls : Array[@types.ToolCallRequest] = [
    @types.ToolCallRequest::new(id="fc_001", name="datetime", arguments={
      "tz": "UTC",
    }),
  ]
  let response = @types.ModelResponse::ToolCalls(calls)
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "output": Array(output), .. } => {
      inspect(output.length(), content="1")
      match output[0] {
        {
          "type": String("function_call"),
          "name": String(name),
          "call_id": String(call_id),
          ..
        } => {
          inspect(name, content="datetime")
          inspect(call_id, content="fc_001")
        }
        _ => fail("Expected function_call output")
      }
    }
    _ => fail("Expected valid response JSON")
  }
}

///|
test "model_response_to_responses_json: web search tool call" {
  let calls : Array[@types.ToolCallRequest] = [
    @types.ToolCallRequest::web_search(
      id="ws_001",
      query=Some("current weather in Tokyo"),
    ),
  ]
  let response = @types.ModelResponse::ToolCalls(calls)
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "output": Array(output), .. } =>
      match output[0] {
        {
          "type": String("web_search_call"),
          "id": String(id),
          "action": { "type": String("search"), "query": String(query), .. },
          ..
        } => {
          assert_eq(id, "ws_001")
          assert_eq(query, "current weather in Tokyo")
        }
        _ => fail("Expected web_search_call output")
      }
    _ => fail("Expected valid response JSON")
  }
}

///|
test "model_response_to_responses_json: rich text preserves annotations and web search traces" {
  let response = @types.ModelResponse::RichText(
    @types.RichTextResponse::new(
      content="Weather details",
      annotations=[
        @types.ResponseAnnotation::url_citation(
          url="https://example.com/weather",
          start_index=0,
          end_index=7,
          title=Some("Weather Source"),
        ),
      ],
      tool_traces=[
        @types.ToolCallTrace::new(
          id="ws_001",
          name="web_search",
          kind=@types.ToolCallKind::WebSearch,
          statuses=[@types.ToolCallStatus::Completed],
          arguments={ "query": "current weather in Tokyo" },
        ),
      ],
    ),
  )
  let json = model_response_to_responses_json(
    response,
    response_id=test_response_id,
    model=test_model,
  )
  match json {
    { "output": Array(output), .. } => {
      assert_eq(output.length(), 2)
      match output[0] {
        { "type": String("web_search_call"), .. } => ()
        _ => fail("Expected web_search_call output")
      }
      match output[1] {
        { "type": String("message"), "content": Array(content_arr), .. } =>
          match content_arr[0] {
            {
              "type": String("output_text"),
              "annotations": Array(annotations),
              ..
            } => assert_eq(annotations.length(), 1)
            _ => fail("Expected annotated output_text")
          }
        _ => fail("Expected message output")
      }
    }
    _ => fail("Expected valid response JSON")
  }
}

// =============================================================================
// Harmony -> Responses API Translator Tests
// =============================================================================

///|
test "HarmonyToResponsesTranslator: text streaming" {
  let translator = HarmonyToResponsesTranslator::new(
    response_id=test_response_id,
  )
  // First chunk with role
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  let events1 = translator.translate(event1)
  inspect(events1.length(), content="2")
  inspect(events1[0].0, content="response.created")
  inspect(events1[1].0, content="response.in_progress")
  // Content chunk
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([{ "index": 0, "delta": { "content": "Hello" } }]),
    },
  }
  let events2 = translator.translate(event2)
  inspect(events2.length(), content="3")
  inspect(events2[0].0, content="response.output_item.added")
  inspect(events2[1].0, content="response.content_part.added")
  inspect(events2[2].0, content="response.output_text.delta")
  // Final chunk with stop
  let event3 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "stop" },
      ]),
    },
  }
  let events3 = translator.translate(event3)
  inspect(events3.length(), content="4")
  inspect(events3[0].0, content="response.output_text.done")
  inspect(events3[1].0, content="response.content_part.done")
  inspect(events3[2].0, content="response.output_item.done")
  inspect(events3[3].0, content="response.completed")
}

///|
test "HarmonyToResponsesTranslator: tool call streaming" {
  let translator = HarmonyToResponsesTranslator::new(
    response_id=test_response_id,
  )
  // First chunk
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  ignore(translator.translate(event1))
  // Tool call chunk
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": {
            "tool_calls": Json::array([
              {
                "id": "fc_xyz",
                "type": "function",
                "function": { "name": "datetime", "arguments": "{}" },
              },
            ]),
          },
        },
      ]),
    },
  }
  let events2 = translator.translate(event2)
  inspect(events2.length(), content="2")
  inspect(events2[0].0, content="response.output_item.added")
  inspect(events2[1].0, content="response.function_call_arguments.delta")
  match events2[1].1 {
    { "output_index": Number(output_index, ..), .. } =>
      assert_eq(output_index.to_int(), 0)
    _ => fail("Missing output_index")
  }
  let event3 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "tool_calls" },
      ]),
    },
  }
  let events3 = translator.translate(event3)
  inspect(events3.length(), content="3")
  inspect(events3[0].0, content="response.function_call_arguments.done")
  inspect(events3[1].0, content="response.output_item.done")
  inspect(events3[2].0, content="response.completed")
}

///|
test "HarmonyToResponsesTranslator: fixture text stream round-trips to Responses API" {
  let translated = translate_harmony_fixture(
    "testdata/groq/harmony/stream/text.jsonl", test_response_id,
  ) catch {
    err => {
      fail("Failed to translate fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_translated_responses(translated)
  match result {
    @types.ModelResponse::Text(text) => assert_eq(text, "4")
    _ => fail("Expected text result")
  }
}

///|
test "HarmonyToResponsesTranslator: fixture multi tool stream keeps chunk routing" {
  let translated = translate_harmony_fixture(
    "testdata/groq/harmony/stream/multi_toolcall.jsonl", test_response_id,
  ) catch {
    err => {
      fail("Failed to translate fixture: " + err.to_string())
      return
    }
  }
  let mut output_item_adds = 0
  let mut first_delta_count = 0
  let mut second_delta_count = 0
  for event in translated {
    if event.event == "response.output_item.added" {
      output_item_adds = output_item_adds + 1
    }
    if event.event == "response.function_call_arguments.delta" {
      match event.data {
        { "output_index": Number(output_index, ..), .. } =>
          if output_index.to_int() == 0 {
            first_delta_count = first_delta_count + 1
          } else if output_index.to_int() == 1 {
            second_delta_count = second_delta_count + 1
          }
        _ => ()
      }
    }
  }
  assert_eq(output_item_adds, 2)
  assert_eq(first_delta_count, 3)
  assert_eq(second_delta_count, 3)
  let result = accumulate_translated_responses(translated)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].name, "search")
      assert_eq(calls[1].name, "calculate")
      inspect(
        calls[0].arguments.stringify(),
        content="{\"q\":\"Tokyo weather\"}",
      )
      inspect(
        calls[1].arguments.stringify(),
        content="{\"expression\":\"2+2\"}",
      )
    }
    _ => fail("Expected tool calls")
  }
}

// =============================================================================
// Round-trip Tests
// =============================================================================

///|
test "responses_request_to_chat_completions: basic request" {
  let request : Json = {
    "model": Json::string(test_model_harmony),
    "input": Json::array([
      { "role": "system", "content": "You are helpful." },
      { "role": "user", "content": "Hello" },
    ]),
  }
  let chat_request = responses_request_to_chat_completions(request)
  match chat_request {
    { "model": String(model), "messages": Array(msgs), "stream": True, .. } => {
      assert_eq(model, test_model_harmony)
      inspect(msgs.length(), content="2")
    }
    _ => fail("Expected valid Chat Completions request")
  }
}

///|
test "responses_request_to_chat_completions: with tools" {
  let request : Json = {
    "model": Json::string(test_model_harmony),
    "input": Json::array([{ "role": "user", "content": "What time?" }]),
    "tools": Json::array([
      {
        "type": "function",
        "function": {
          "name": "datetime",
          "description": "Get time",
          "parameters": {},
        },
      },
    ]),
    "tool_choice": "auto",
  }
  let chat_request = responses_request_to_chat_completions(request)
  match chat_request {
    { "tools": Array(tools), "tool_choice": String(choice), .. } => {
      inspect(tools.length(), content="1")
      inspect(choice, content="auto")
    }
    _ => fail("Expected tools in request")
  }
}

///|
test "responses_request_to_chat_completions: maps web search tool to function tool" {
  let request : Json = {
    "model": Json::string(test_model_harmony),
    "input": Json::array([{ "role": "user", "content": "Search the web" }]),
    "tools": Json::array([
      { "type": "web_search_preview", "search_context_size": "medium" },
    ]),
  }
  let chat_request = responses_request_to_chat_completions(request)
  match chat_request {
    { "tools": Array(tools), .. } =>
      match tools[0] {
        {
          "type": String("function"),
          "function": { "name": String(name), .. },
          ..
        } => assert_eq(name, "web_search")
        _ => fail("Expected mapped function tool")
      }
    _ => fail("Expected tools in request")
  }
}

// =============================================================================
// E2E: Responses API request → Harmony conversion → Groq response → ModelResponse
//
// Fixture triplets per turn:
//   *_request.json  — Responses API input (what client sends)
//   *_stream.txt    — Groq streaming SSE response (backend output)
//   *_sync.json     — Groq synchronous JSON response (backend output)
//
// Tests verify the full chain:
//   1. request fixture → responses_request_to_chat_completions → valid Chat Completions
//   2. response fixture (stream) → translator pipeline → ModelResponse
//   3. response fixture (sync) → synthetic pipeline → ModelResponse
//   4. stream == sync equivalence
// =============================================================================

///|
fn strip_sse_to_jsonl(raw : String) -> String {
  let buf = StringBuilder::new()
  for line in @utils.split_lines(raw) {
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("data: ") {
      let content = StringBuilder::new()
      let mut idx = 0
      for c in trimmed {
        if idx >= 6 {
          content.write_char(c)
        }
        idx = idx + 1
      }
      let c = content.to_string()
      if c != "[DONE]" {
        buf.write_string(c + "\n")
      }
    }
  }
  buf.to_string()
}

///|
fn streaming_fixture_to_model_response(
  path : String,
  response_id : String,
) -> @types.ModelResponse raise {
  let raw = @utils.read_testdata(path)
  let events = @sse.parse_jsonl(strip_sse_to_jsonl(raw))
  let translator = HarmonyToResponsesTranslator::new(response_id~)
  let acc = @openai.ResponsesApiAccumulator::new()
  for event in events {
    for pair in translator.translate(event) {
      let wire = @sse.format_sse_event(pair.0, pair.1)
      for e in @sse.parse_sse_chunk(wire).events {
        acc.feed(e)
      }
    }
  }
  acc.finish()
}

///|
fn sync_fixture_to_model_response(
  path : String,
  response_id : String,
) -> @types.ModelResponse raise {
  let raw = @utils.read_testdata(path)
  let json = @json.parse(raw)
  let events = chat_completion_to_synthetic_events(json)
  let translator = HarmonyToResponsesTranslator::new(response_id~)
  let acc = @openai.ResponsesApiAccumulator::new()
  for event in events {
    for pair in translator.translate(event) {
      let wire = @sse.format_sse_event(pair.0, pair.1)
      for e in @sse.parse_sse_chunk(wire).events {
        acc.feed(e)
      }
    }
  }
  acc.finish()
}

// --- Input: Responses API request → Harmony Chat Completions conversion ---

///|
test "e2e/input/turn1: request fixture → harmony conversion has tools and stream" {
  let raw = @utils.read_testdata(
    "testdata/groq/harmony/multiturn_toolcall/turn1_request.json",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let request = @json.parse(raw) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let chat = responses_request_to_chat_completions(request, stream=true)
  // Must have stream=true
  match chat {
    { "stream": True, .. } => ()
    _ => fail("Expected stream=true")
  }
  // Must have tools with nested function format
  match chat {
    { "tools": Array(tools), .. } => {
      assert_eq(tools.length(), 1)
      match tools[0] {
        {
          "type": String("function"),
          "function": { "name": String(n), .. },
          ..
        } => assert_eq(n, "datetime")
        _ => fail("Expected nested function tool format")
      }
    }
    _ => fail("Expected tools")
  }
  // Must have system message from instructions + user message
  match chat {
    { "messages": Array(msgs), .. } => {
      assert_eq(msgs.length(), 2)
      match msgs[0] {
        { "role": String("system"), "content": String(c), .. } =>
          assert_eq(c, "Be concise")
        _ => fail("Expected system message")
      }
    }
    _ => fail("Expected messages")
  }
}

///|
test "e2e/input/turn2: request fixture → harmony conversion has multiturn with tool result" {
  let raw = @utils.read_testdata(
    "testdata/groq/harmony/multiturn_toolcall/turn2_request.json",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let request = @json.parse(raw) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let chat = responses_request_to_chat_completions(request, stream=true)
  match chat {
    { "messages": Array(msgs), .. } => {
      // system, user, assistant(tool_calls), tool(result), user
      assert_eq(msgs.length(), 5)
      // assistant message must have tool_calls
      match msgs[2] {
        { "role": String("assistant"), "tool_calls": Array(tc), .. } =>
          assert_eq(tc.length(), 1)
        _ => fail("Expected assistant with tool_calls")
      }
      // tool result message
      match msgs[3] {
        { "role": String("tool"), "content": String(c), .. } =>
          assert_true(c.contains("2026-03-18"))
        _ => fail("Expected tool message")
      }
      // follow-up user message
      match msgs[4] {
        { "role": String("user"), "content": String(c), .. } =>
          assert_true(c.contains("day of the week"))
        _ => fail("Expected user follow-up")
      }
    }
    _ => fail("Expected messages")
  }
}

// --- Output: Groq response → pipeline → ModelResponse ---

///|
test "e2e/output/turn1/stream: tool call name" {
  match
    streaming_fixture_to_model_response(
      "testdata/groq/harmony/multiturn_toolcall/turn1_stream.txt", "r",
    ) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "datetime")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "e2e/output/turn1/sync: tool call name" {
  match
    sync_fixture_to_model_response(
      "testdata/groq/harmony/multiturn_toolcall/turn1_sync.json", "r",
    ) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "datetime")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "e2e/output/turn1/equiv: stream == sync" {
  let s = streaming_fixture_to_model_response(
    "testdata/groq/harmony/multiturn_toolcall/turn1_stream.txt", "r",
  )
  let n = sync_fixture_to_model_response(
    "testdata/groq/harmony/multiturn_toolcall/turn1_sync.json", "r",
  )
  match (s, n) {
    (@types.ModelResponse::ToolCalls(a), @types.ModelResponse::ToolCalls(b)) => {
      assert_eq(a[0].name, b[0].name)
      assert_eq(a[0].arguments.stringify(), b[0].arguments.stringify())
    }
    _ => fail("Both should be ToolCalls")
  }
}

///|
test "e2e/output/turn2/stream: text references Wednesday" {
  match
    streaming_fixture_to_model_response(
      "testdata/groq/harmony/multiturn_toolcall/turn2_stream.txt", "r",
    ) {
    @types.ModelResponse::Text(text) => assert_true(text.contains("Wednesday"))
    _ => fail("Expected Text")
  }
}

///|
test "e2e/output/turn2/sync: text references Wednesday" {
  match
    sync_fixture_to_model_response(
      "testdata/groq/harmony/multiturn_toolcall/turn2_sync.json", "r",
    ) {
    @types.ModelResponse::Text(text) => assert_true(text.contains("Wednesday"))
    _ => fail("Expected Text")
  }
}

///|
test "e2e/output/turn2/equiv: stream == sync" {
  let s = streaming_fixture_to_model_response(
    "testdata/groq/harmony/multiturn_toolcall/turn2_stream.txt", "r",
  )
  let n = sync_fixture_to_model_response(
    "testdata/groq/harmony/multiturn_toolcall/turn2_sync.json", "r",
  )
  match (s, n) {
    (@types.ModelResponse::Text(a), @types.ModelResponse::Text(b)) => {
      assert_true(a.contains("Wednesday"))
      assert_true(b.contains("Wednesday"))
    }
    _ => fail("Both should be Text")
  }
}

// --- Lifecycle ---

///|
test "e2e/lifecycle/turn1/stream: created → function_call → completed" {
  let raw = @utils.read_testdata(
    "testdata/groq/harmony/multiturn_toolcall/turn1_stream.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let events = @sse.parse_jsonl(strip_sse_to_jsonl(raw)) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let translator = HarmonyToResponsesTranslator::new(response_id="r")
  let types : Array[String] = []
  for event in events {
    for pair in translator.translate(event) {
      types.push(pair.0)
    }
  }
  assert_eq(types[0], "response.created")
  assert_eq(types[1], "response.in_progress")
  assert_eq(types[types.length() - 1], "response.completed")
  assert_true(types.contains("response.output_item.added"))
  assert_true(types.contains("response.function_call_arguments.done"))
}

///|
test "e2e/lifecycle/turn2/stream: created → text_delta → completed" {
  let raw = @utils.read_testdata(
    "testdata/groq/harmony/multiturn_toolcall/turn2_stream.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let events = @sse.parse_jsonl(strip_sse_to_jsonl(raw)) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let translator = HarmonyToResponsesTranslator::new(response_id="r")
  let types : Array[String] = []
  for event in events {
    for pair in translator.translate(event) {
      types.push(pair.0)
    }
  }
  assert_eq(types[0], "response.created")
  assert_eq(types[types.length() - 1], "response.completed")
  assert_true(types.contains("response.output_text.delta"))
  assert_true(types.contains("response.output_text.done"))
}
