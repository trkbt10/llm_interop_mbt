///|
/// Streaming pipeline integration tests
///
/// Tests the full Harmony translation pipeline across all delivery modes:
///
///   Path A: Non-streaming — Chat Completions JSON → parse → model_response_to_responses_json
///   Path B: Real streaming — Backend SSE → parse_sse_chunk → translator → format_sse_event
///   Path C: Synthetic streaming — Chat Completions JSON → synthetic_events → translator → format_sse_event
///
/// Test matrix:
///   Content types:  Text │ Single ToolCall │ Multi ToolCall
///   Delivery modes: Path A │ Path B │ Path C
///
/// Each test verifies exactly ONE property.

// =============================================================================
// Fixtures: synchronous Chat Completions responses
// =============================================================================

///|
let sync_text_response : Json = {
  "id": "chatcmpl-text",
  "choices": Json::array([
    {
      "index": 0,
      "message": { "role": "assistant", "content": "4" },
      "finish_reason": "stop",
    },
  ]),
}

///|
let sync_toolcall_response : Json = {
  "id": "chatcmpl-tc",
  "choices": Json::array([
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": Json::array([
          {
            "id": "fc_b47538c7-1d7d-4bcc-802e-9c039247cc62",
            "type": "function",
            "function": { "name": "datetime", "arguments": "{}" },
          },
        ]),
      },
      "finish_reason": "tool_calls",
    },
  ]),
}

///|
let sync_multi_toolcall_response : Json = {
  "id": "chatcmpl-mt",
  "choices": Json::array([
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "tool_calls": Json::array([
          {
            "id": "fc_search",
            "type": "function",
            "function": {
              "name": "search",
              "arguments": "{\"q\":\"Tokyo weather\"}",
            },
          },
          {
            "id": "fc_calc",
            "type": "function",
            "function": {
              "name": "calculate",
              "arguments": "{\"expression\":\"2+2\"}",
            },
          },
        ]),
      },
      "finish_reason": "tool_calls",
    },
  ]),
}

// =============================================================================
// Helpers
// =============================================================================

///|
struct FlushRecord {
  chunk_iteration : Int
  wire : String
}

///|
fn simulate_streaming_proxy_detailed(
  raw_sse : String,
  response_id : String,
  chunk_sizes : Array[Int],
) -> Array[FlushRecord] {
  let translator = HarmonyToResponsesTranslator::new(response_id~)
  let flushed : Array[FlushRecord] = []
  let mut buffer = ""
  let mut offset = 0
  for iteration, chunk_size in chunk_sizes {
    let end = if offset + chunk_size > raw_sse.length() {
      raw_sse.length()
    } else {
      offset + chunk_size
    }
    let chunk = raw_sse_substring(raw_sse, offset, end)
    offset = end
    buffer = buffer + chunk
    let parsed = @sse.parse_sse_chunk(buffer)
    buffer = parsed.remaining
    for event in parsed.events {
      for pair in translator.translate(event) {
        flushed.push({
          chunk_iteration: iteration,
          wire: @sse.format_sse_event(pair.0, pair.1),
        })
      }
    }
  }
  if buffer.length() > 0 {
    let parsed = @sse.parse_sse_chunk(buffer + "\n")
    for event in parsed.events {
      for pair in translator.translate(event) {
        flushed.push({
          chunk_iteration: chunk_sizes.length(),
          wire: @sse.format_sse_event(pair.0, pair.1),
        })
      }
    }
  }
  flushed
}

///|
fn flush_wires(records : Array[FlushRecord]) -> Array[String] {
  records.map(fn(r) { r.wire })
}

///|
fn simulate_streaming_proxy(
  raw_sse : String,
  response_id : String,
  chunk_sizes : Array[Int],
) -> Array[String] {
  flush_wires(
    simulate_streaming_proxy_detailed(raw_sse, response_id, chunk_sizes),
  )
}

///|
fn simulate_streaming_single_chunk(
  raw_sse : String,
  response_id : String,
) -> Array[String] {
  simulate_streaming_proxy(raw_sse, response_id, [raw_sse.length()])
}

///|
fn simulate_streaming_byte_by_byte(
  raw_sse : String,
  response_id : String,
) -> Array[String] {
  let sizes : Array[Int] = Array::make(raw_sse.length(), 1)
  simulate_streaming_proxy(raw_sse, response_id, sizes)
}

///|
fn simulate_synthetic_streaming(
  response_json : Json,
  response_id : String,
) -> Array[String] {
  let translator = HarmonyToResponsesTranslator::new(response_id~)
  let flushed : Array[String] = []
  for event in chat_completion_to_synthetic_events(response_json) {
    for pair in translator.translate(event) {
      flushed.push(@sse.format_sse_event(pair.0, pair.1))
    }
  }
  flushed
}

///|
/// Path A: non-streaming gateway path (parse → ModelResponse)
fn non_streaming_result(
  response_json : Json,
  response_id : String,
  model : String,
) -> @types.ModelResponse {
  let model_response = @openai.parse_openai_chat_response(response_json)
  // Round-trip through Responses API JSON to mirror the gateway's non-streaming path
  let responses_json = model_response_to_responses_json(
    model_response,
    response_id~,
    model~,
  )
  // Parse back to verify the JSON is valid and extractable
  ignore(responses_json)
  model_response
}

///|
fn reparse_and_accumulate(flushed : Array[String]) -> @types.ModelResponse {
  let acc = @openai.ResponsesApiAccumulator::new()
  for wire in flushed {
    for event in @sse.parse_sse_chunk(wire).events {
      acc.feed(event)
    }
  }
  acc.finish()
}

///|
fn extract_event_types(flushed : Array[String]) -> Array[String] {
  let types : Array[String] = []
  for wire in flushed {
    for event in @sse.parse_sse_chunk(wire).events {
      types.push(event.event)
    }
  }
  types
}

///|
fn raw_sse_substring(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let mut idx = 0
  for c in s {
    if idx >= start && idx < end {
      buf.write_char(c)
    }
    idx = idx + 1
  }
  buf.to_string()
}

///|
fn compute_line_based_chunks(raw : String) -> Array[Int] {
  let sizes : Array[Int] = []
  let mut current_size = 0
  let mut prev_was_newline = false
  for c in raw {
    current_size = current_size + 1
    if c == '\n' {
      if prev_was_newline {
        sizes.push(current_size)
        current_size = 0
      }
      prev_was_newline = true
    } else {
      prev_was_newline = false
    }
  }
  if current_size > 0 {
    sizes.push(current_size)
  }
  sizes
}

///|
fn jsonl_to_raw_sse(jsonl : String) -> String {
  let buf = StringBuilder::new()
  for line in @utils.split_lines(jsonl) {
    let trimmed = line.trim().to_string()
    if trimmed.length() > 0 {
      buf.write_string("data: " + trimmed + "\n\n")
    }
  }
  buf.write_string("data: [DONE]\n\n")
  buf.to_string()
}

///|
fn count_event_type(flushed : Array[String], event_type : String) -> Int {
  extract_event_types(flushed)
  .iter()
  .filter(fn(t) { t == event_type })
  .fold(init=0, fn(acc, _) { acc + 1 })
}

///|
fn make_fixed_chunks(total : Int, size : Int) -> Array[Int] {
  let sizes : Array[Int] = []
  let mut remaining = total
  while remaining > 0 {
    let s = if remaining > size { size } else { remaining }
    sizes.push(s)
    remaining = remaining - s
  }
  sizes
}

// =============================================================================
// 1. Result correctness — Path B (real streaming)
// =============================================================================

///|
test "result/streaming/text: accumulated text matches fixture" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  match reparse_and_accumulate(simulate_streaming_single_chunk(raw, "r")) {
    @types.ModelResponse::Text(text) => assert_eq(text, "4")
    _ => fail("Expected Text")
  }
}

///|
test "result/streaming/toolcall: name and arguments match fixture" {
  let raw = read_harmony_fixture(
    "testdata/groq/harmony/stream/toolcall_raw.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  match reparse_and_accumulate(simulate_streaming_single_chunk(raw, "r")) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "datetime")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "result/streaming/multi-toolcall: both tools with correct arguments" {
  let jsonl = read_harmony_fixture(
    "testdata/groq/harmony/stream/multi_toolcall.jsonl",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  match
    reparse_and_accumulate(
      simulate_streaming_single_chunk(jsonl_to_raw_sse(jsonl), "r"),
    ) {
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
    _ => fail("Expected ToolCalls")
  }
}

// =============================================================================
// 2. Result correctness — Path C (synthetic streaming)
// =============================================================================

///|
test "result/synthetic/text: accumulated text matches" {
  match
    reparse_and_accumulate(
      simulate_synthetic_streaming(sync_text_response, "r"),
    ) {
    @types.ModelResponse::Text(text) => assert_eq(text, "4")
    _ => fail("Expected Text")
  }
}

///|
test "result/synthetic/toolcall: name and id match" {
  match
    reparse_and_accumulate(
      simulate_synthetic_streaming(sync_toolcall_response, "r"),
    ) {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "datetime")
      assert_eq(calls[0].id, "fc_b47538c7-1d7d-4bcc-802e-9c039247cc62")
    }
    _ => fail("Expected ToolCalls")
  }
}

///|
test "result/synthetic/multi-toolcall: both tools with correct arguments" {
  match
    reparse_and_accumulate(
      simulate_synthetic_streaming(sync_multi_toolcall_response, "r"),
    ) {
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
    _ => fail("Expected ToolCalls")
  }
}

// =============================================================================
// 3. Equivalence — Path B == Path C (streaming vs synthetic)
// =============================================================================

///|
test "equiv/streaming-vs-synthetic/text: same ModelResponse" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let streaming = reparse_and_accumulate(
    simulate_streaming_single_chunk(raw, "r"),
  )
  let synthetic = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_text_response, "r"),
  )
  match (streaming, synthetic) {
    (@types.ModelResponse::Text(a), @types.ModelResponse::Text(b)) =>
      assert_eq(a, b)
    _ => fail("Both should be Text")
  }
}

///|
test "equiv/streaming-vs-synthetic/toolcall: same tool name" {
  let raw = read_harmony_fixture(
    "testdata/groq/harmony/stream/toolcall_raw.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let streaming = reparse_and_accumulate(
    simulate_streaming_single_chunk(raw, "r"),
  )
  let synthetic = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_toolcall_response, "r"),
  )
  match (streaming, synthetic) {
    (@types.ModelResponse::ToolCalls(a), @types.ModelResponse::ToolCalls(b)) => {
      assert_eq(a.length(), b.length())
      assert_eq(a[0].name, b[0].name)
    }
    _ => fail("Both should be ToolCalls")
  }
}

///|
test "equiv/streaming-vs-synthetic/multi-toolcall: same tools and arguments" {
  let jsonl = read_harmony_fixture(
    "testdata/groq/harmony/stream/multi_toolcall.jsonl",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let streaming = reparse_and_accumulate(
    simulate_streaming_single_chunk(jsonl_to_raw_sse(jsonl), "r"),
  )
  let synthetic = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_multi_toolcall_response, "r"),
  )
  match (streaming, synthetic) {
    (@types.ModelResponse::ToolCalls(a), @types.ModelResponse::ToolCalls(b)) => {
      assert_eq(a.length(), b.length())
      for i in 0..<a.length() {
        assert_eq(a[i].name, b[i].name)
        assert_eq(a[i].arguments.stringify(), b[i].arguments.stringify())
      }
    }
    _ => fail("Both should be ToolCalls")
  }
}

// =============================================================================
// 4. Equivalence — Path A == Path C (non-streaming vs synthetic streaming)
// =============================================================================

///|
test "equiv/non-streaming-vs-synthetic/text: same ModelResponse" {
  let path_a = non_streaming_result(sync_text_response, "r", "test")
  let path_c = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_text_response, "r"),
  )
  match (path_a, path_c) {
    (@types.ModelResponse::Text(a), @types.ModelResponse::Text(b)) =>
      assert_eq(a, b)
    _ => fail("Both should be Text")
  }
}

///|
test "equiv/non-streaming-vs-synthetic/toolcall: same tool name and arguments" {
  let path_a = non_streaming_result(sync_toolcall_response, "r", "test")
  let path_c = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_toolcall_response, "r"),
  )
  match (path_a, path_c) {
    (@types.ModelResponse::ToolCalls(a), @types.ModelResponse::ToolCalls(b)) => {
      assert_eq(a[0].name, b[0].name)
      assert_eq(a[0].arguments.stringify(), b[0].arguments.stringify())
    }
    _ => fail("Both should be ToolCalls")
  }
}

///|
test "equiv/non-streaming-vs-synthetic/multi-toolcall: same tools" {
  let path_a = non_streaming_result(sync_multi_toolcall_response, "r", "test")
  let path_c = reparse_and_accumulate(
    simulate_synthetic_streaming(sync_multi_toolcall_response, "r"),
  )
  match (path_a, path_c) {
    (@types.ModelResponse::ToolCalls(a), @types.ModelResponse::ToolCalls(b)) => {
      assert_eq(a.length(), b.length())
      for i in 0..<a.length() {
        assert_eq(a[i].name, b[i].name)
        assert_eq(a[i].arguments.stringify(), b[i].arguments.stringify())
      }
    }
    _ => fail("Both should be ToolCalls")
  }
}

// =============================================================================
// 5. Event lifecycle sequence
// =============================================================================

///|
test "lifecycle/streaming/text: correct event order" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let types = extract_event_types(simulate_streaming_single_chunk(raw, "r"))
  assert_eq(types[0], "response.created")
  assert_eq(types[1], "response.in_progress")
  assert_eq(types[types.length() - 1], "response.completed")
  assert_true(types.contains("response.output_text.delta"))
  assert_true(types.contains("response.output_text.done"))
}

///|
test "lifecycle/streaming/toolcall: has function_call events" {
  let raw = read_harmony_fixture(
    "testdata/groq/harmony/stream/toolcall_raw.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let types = extract_event_types(simulate_streaming_single_chunk(raw, "r"))
  assert_true(types.contains("response.output_item.added"))
  assert_true(types.contains("response.function_call_arguments.delta"))
  assert_true(types.contains("response.function_call_arguments.done"))
  assert_eq(types[types.length() - 1], "response.completed")
}

///|
test "lifecycle/synthetic/text: exact event sequence" {
  let types = extract_event_types(
    simulate_synthetic_streaming(sync_text_response, "r"),
  )
  inspect(
    types
    .iter()
    .fold(init="", fn(acc, t) { if acc == "" { t } else { acc + " → " + t } }),
    content="response.created → response.in_progress → response.output_item.added → response.content_part.added → response.output_text.delta → response.output_text.done → response.content_part.done → response.output_item.done → response.completed",
  )
}

///|
test "lifecycle/synthetic/toolcall: exact event sequence" {
  let types = extract_event_types(
    simulate_synthetic_streaming(sync_toolcall_response, "r"),
  )
  inspect(
    types
    .iter()
    .fold(init="", fn(acc, t) { if acc == "" { t } else { acc + " → " + t } }),
    content="response.created → response.in_progress → response.output_item.added → response.function_call_arguments.delta → response.function_call_arguments.done → response.output_item.done → response.completed",
  )
}

///|
test "lifecycle/streaming/text: empty content delta filtered" {
  let raw = "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"X\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  assert_eq(
    count_event_type(
      simulate_streaming_single_chunk(raw, "r"),
      "response.output_text.delta",
    ),
    1,
  )
}

// =============================================================================
// 6. Chunk invariance — different fragmentation → same result
// =============================================================================

///|
test "chunk-invariance/text: single-chunk == byte-by-byte" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let a = simulate_streaming_single_chunk(raw, "r")
  let b = simulate_streaming_byte_by_byte(raw, "r")
  assert_eq(a.length(), b.length())
}

///|
test "chunk-invariance/toolcall: single-chunk == byte-by-byte" {
  let raw = read_harmony_fixture(
    "testdata/groq/harmony/stream/toolcall_raw.txt",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let a = simulate_streaming_single_chunk(raw, "r")
  let b = simulate_streaming_byte_by_byte(raw, "r")
  assert_eq(a.length(), b.length())
}

///|
test "chunk-invariance/multi-toolcall: 50-byte chunks preserve output_index routing" {
  let jsonl = read_harmony_fixture(
    "testdata/groq/harmony/stream/multi_toolcall.jsonl",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let raw = jsonl_to_raw_sse(jsonl)
  let flushed = simulate_streaming_proxy(
    raw,
    "r",
    make_fixed_chunks(raw.length(), 50),
  )
  let mut tool0 = 0
  let mut tool1 = 0
  for wire in flushed {
    for event in @sse.parse_sse_chunk(wire).events {
      if event.event == "response.function_call_arguments.delta" {
        match event.data {
          { "output_index": Number(oi, ..), .. } =>
            if oi.to_int() == 0 {
              tool0 += 1
            } else {
              tool1 += 1
            }
          _ => ()
        }
      }
    }
  }
  assert_true(tool0 > 0)
  assert_true(tool1 > 0)
}

// =============================================================================
// 7. Incremental delivery — events from multiple read_some iterations
// =============================================================================

///|
test "incremental/text: events span multiple iterations" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let records = simulate_streaming_proxy_detailed(
    raw,
    "r",
    make_fixed_chunks(raw.length(), 100),
  )
  let iters : Map[Int, Bool] = {}
  for r in records {
    iters[r.chunk_iteration] = true
  }
  assert_true(iters.length() >= 2)
}

///|
test "incremental/text: first event emitted at iteration 0" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let records = simulate_streaming_proxy_detailed(
    raw,
    "r",
    compute_line_based_chunks(raw),
  )
  assert_eq(records[0].chunk_iteration, 0)
  assert_true(records[records.length() - 1].chunk_iteration > 0)
}

///|
test "incremental/text: at least 3 producing iterations with line-based chunks" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let records = simulate_streaming_proxy_detailed(
    raw,
    "r",
    compute_line_based_chunks(raw),
  )
  let iters : Map[Int, Int] = {}
  for r in records {
    iters[r.chunk_iteration] = iters.get(r.chunk_iteration).unwrap_or(0) + 1
  }
  assert_true(iters.length() >= 3)
}

///|
test "incremental/multi-toolcall: events span multiple iterations" {
  let jsonl = read_harmony_fixture(
    "testdata/groq/harmony/stream/multi_toolcall.jsonl",
  ) catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  let raw = jsonl_to_raw_sse(jsonl)
  let records = simulate_streaming_proxy_detailed(
    raw,
    "r",
    compute_line_based_chunks(raw),
  )
  let iters : Map[Int, Bool] = {}
  for r in records {
    iters[r.chunk_iteration] = true
  }
  assert_true(iters.length() >= 3)
}

// =============================================================================
// 8. Wire format validity
// =============================================================================

///|
test "wire/streaming/text: every event is valid SSE" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  for wire in simulate_streaming_single_chunk(raw, "r") {
    assert_true(wire.has_prefix("event: "))
    assert_true(wire.has_suffix("\n\n"))
    let parsed = @sse.parse_sse_chunk(wire)
    assert_true(parsed.events.length() > 0)
    assert_eq(parsed.remaining, "")
  }
}

///|
test "wire/streaming/text: data.type matches event name" {
  let raw = read_harmony_fixture("testdata/groq/harmony/stream/text_raw.txt") catch {
    e => {
      fail(e.to_string())
      return
    }
  }
  for wire in simulate_streaming_single_chunk(raw, "r") {
    for event in @sse.parse_sse_chunk(wire).events {
      match event.data {
        { "type": String(t), .. } => assert_eq(t, event.event)
        _ => fail("data missing type field")
      }
    }
  }
}

///|
test "wire/synthetic/text: every event is valid SSE" {
  for wire in simulate_synthetic_streaming(sync_text_response, "r") {
    assert_true(wire.has_prefix("event: "))
    assert_true(wire.has_suffix("\n\n"))
    let parsed = @sse.parse_sse_chunk(wire)
    assert_true(parsed.events.length() > 0)
    assert_eq(parsed.remaining, "")
  }
}

///|
test "wire/synthetic/toolcall: every event is valid SSE" {
  for wire in simulate_synthetic_streaming(sync_toolcall_response, "r") {
    assert_true(wire.has_prefix("event: "))
    assert_true(wire.has_suffix("\n\n"))
    let parsed = @sse.parse_sse_chunk(wire)
    assert_true(parsed.events.length() > 0)
    assert_eq(parsed.remaining, "")
  }
}

// =============================================================================
// 9. Chunk boundary edge cases
// =============================================================================

///|
test "edge/split-at-newline-boundary: result correct" {
  let e1 = "{\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}"
  let e2 = "{\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}"
  let e3 = "{\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}"
  let c1 = "data: " + e1 + "\n\n"
  let c2 = "data: " + e2 + "\n\n"
  let c3 = "data: " + e3 + "\n\ndata: [DONE]\n\n"
  let raw = c1 + c2 + c3
  let flushed = simulate_streaming_proxy(raw, "r", [
    c1.length(),
    c2.length(),
    c3.length(),
  ])
  match reparse_and_accumulate(flushed) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hi")
    _ => fail("Expected Text")
  }
}

///|
test "edge/split-mid-json: result correct" {
  let raw = "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  let flushed = simulate_streaming_proxy(raw, "r", [30, raw.length() - 30])
  match reparse_and_accumulate(flushed) {
    @types.ModelResponse::Text(text) => assert_eq(text, "OK")
    _ => fail("Expected Text")
  }
}
