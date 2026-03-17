///|
/// Harmony dialect accumulator tests

///|
fn read_sse_fixture(path : String) -> String raise {
  @fs.read_file_to_string(path)
}

// =============================================================================
// Harmony Accumulator Tests
// =============================================================================

///|
test "HarmonyAccumulator captures reasoning" {
  let acc = HarmonyAccumulator::new()
  let event1 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "reasoning": "Let me think...", "channel": "analysis" },
        },
      ]),
    },
  }
  let event2 : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": { "content": "The answer is 42", "channel": "final" },
          "finish_reason": "stop",
        },
      ]),
    },
  }
  acc.feed(event1)
  acc.feed(event2)
  let result = acc.finish()
  let reasoning = acc.get_reasoning()
  match result {
    @types.ModelResponse::Text(content) =>
      inspect(content, content="The answer is 42")
    _ => fail("Expected Text response")
  }
  inspect(reasoning, content="Let me think...")
}

///|
test "accumulate_harmony handles tool calls" {
  let jsonl =
    #| {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"tool_calls":[{"id":"fc_123","type":"function","function":{"name":"datetime","arguments":"{}"}}]},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
  let result = accumulate_harmony(jsonl)
  match result {
    @types.ModelResponse::ToolCalls(calls) => {
      inspect(calls.length(), content="1")
      inspect(calls[0].id, content="fc_123")
      inspect(calls[0].name, content="datetime")
    }
    _ => fail("Expected ToolCalls response")
  }
}

///|
test "accumulate_harmony fixture multi tool stream keeps arguments by index" {
  let jsonl = read_sse_fixture(
    "testdata/sse_fixtures/groq/harmony/multi_toolcall_stream.jsonl",
  ) catch {
    err => {
      fail("Failed to read fixture: " + err.to_string())
      return
    }
  }
  let result = accumulate_harmony(jsonl) catch {
    err => {
      fail("Failed to accumulate harmony fixture: " + err.to_string())
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
