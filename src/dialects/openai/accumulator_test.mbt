///|
/// OpenAI dialect accumulator tests

///|
fn read_sse_fixture(path : String) -> String raise {
  @fs.read_file_to_string(path)
}

// =============================================================================
// Chat Completions Accumulator Tests
// =============================================================================

///|
test "ChatCompletionsAccumulator accumulates text" {
  let acc = ChatCompletionsAccumulator::new()
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([{ "index": 0, "delta": { "content": "Hello, " } }]),
    },
  }
  let event3 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "content": "world!" },
          "finish_reason": "stop",
        },
      ]),
    },
  }
  acc.feed(event1)
  acc.feed(event2)
  acc.feed(event3)
  let result = acc.finish()
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello, world!")
    _ => fail("Expected Text response")
  }
}

///|
test "ChatCompletionsAccumulator handles tool calls" {
  let jsonl =
    #| {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"tool_calls":[{"id":"fc_123","type":"function","function":{"name":"datetime","arguments":"{}"}}]},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
  let result = accumulate_chat_completions(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected ToolCalls response")
  }
}

// =============================================================================
// Responses API Accumulator Tests
// =============================================================================

///|
test "ResponsesApiAccumulator text stream" {
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"Hello","sequence_number":1}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":" World","sequence_number":2}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":3}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="Hello World")
    _ => fail("Expected Text response")
  }
}

///|
test "ResponsesApiAccumulator tool call stream" {
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_item.added","data":{"type":"response.output_item.added","item":{"type":"function_call","call_id":"fc_001","name":"get_weather"},"sequence_number":1}}
    #| {"event":"response.function_call_arguments.delta","data":{"type":"response.function_call_arguments.delta","delta":"{\"city\":\"Tokyo\"}","sequence_number":2}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":3}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].name, content="get_weather")
      inspect(calls[0].id, content="fc_001")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "ResponsesApiAccumulator fixture multi tool stream routes deltas by output_index" {
  let jsonl = read_sse_fixture(
    "testdata/openai/responses/multi_toolcall_stream.jsonl",
  ) catch {
    err => {
      fail("Failed to read fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_responses_api(jsonl) catch {
    err => {
      fail("Failed to accumulate responses fixture: " + err.to_string())
      return
    }
  }
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].id, "fc_search")
      assert_eq(calls[0].name, "search")
      inspect(
        calls[0].arguments.stringify(),
        content="{\"q\":\"Tokyo weather\"}",
      )
      assert_eq(calls[1].id, "fc_calc")
      assert_eq(calls[1].name, "calculate")
      inspect(
        calls[1].arguments.stringify(),
        content="{\"expression\":\"2+2\"}",
      )
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "ResponsesApiAccumulator fixture web search stream returns final text" {
  let jsonl = read_sse_fixture(
    "testdata/openai/responses/websearch_stream.jsonl",
  ) catch {
    err => {
      fail("Failed to read fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_responses_api(jsonl) catch {
    err => {
      fail("Failed to accumulate websearch fixture: " + err.to_string())
      return
    }
  }
  match result {
    @types.ModelResponse::RichText(rich) => {
      assert_true(rich.content.contains("weather in Tokyo"))
      assert_true(rich.content.contains("Mostly sunny"))
      assert_eq(rich.tool_traces.length(), 1)
    }
    _ => fail("Expected Text response")
  }
}

///|
test "ResponsesApiAccumulator preserves annotations and web search statuses" {
  let jsonl =
    #| {"event":"response.output_item.added","data":{"type":"response.output_item.added","item":{"id":"ws_001","type":"web_search_call","status":"in_progress","action":{"type":"search"}},"output_index":0,"sequence_number":1}}
    #| {"event":"response.web_search_call.in_progress","data":{"type":"response.web_search_call.in_progress","item_id":"ws_001","output_index":0,"sequence_number":2}}
    #| {"event":"response.web_search_call.searching","data":{"type":"response.web_search_call.searching","item_id":"ws_001","output_index":0,"sequence_number":3}}
    #| {"event":"response.web_search_call.completed","data":{"type":"response.web_search_call.completed","item_id":"ws_001","output_index":0,"sequence_number":4}}
    #| {"event":"response.output_item.done","data":{"type":"response.output_item.done","item":{"id":"ws_001","type":"web_search_call","status":"completed","action":{"type":"search","query":"current weather in Tokyo"}},"output_index":0,"sequence_number":5}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"Weather details","sequence_number":6}}
    #| {"event":"response.output_text.annotation.added","data":{"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://example.com/weather","title":"Weather Source","start_index":0,"end_index":7},"sequence_number":7}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":8}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      assert_eq(rich.tool_traces.length(), 1)
      assert_eq(rich.tool_traces[0].statuses.length(), 3)
      match rich.tool_traces[0].arguments {
        { "query": String(query), .. } =>
          assert_eq(query, "current weather in Tokyo")
        _ => fail("Expected query")
      }
    }
    _ => fail("Expected RichText response")
  }
}
