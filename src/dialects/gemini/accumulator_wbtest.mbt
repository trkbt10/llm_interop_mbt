///|
/// Whitebox coverage for Gemini accumulator paths

///|
test "GeminiAccumulator accumulates text and ignores unparsable chunks" {
  let acc = GeminiAccumulator::new()
  assert_false(acc.finished)

  acc.feed({ event: "data", data: { "other": true } })
  acc.feed({
    event: "data",
    data: {
      "candidates": [
        {
          "content": { "role": "model", "parts": [{ "text": "Hello Gemini" }] },
        },
      ],
    },
  })

  match acc.finish() {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello Gemini")
    _ => fail("Expected text response")
  }
  assert_true(acc.finished)
}

///|
test "GeminiAccumulator returns tool calls with content and falls back invalid arguments" {
  let acc = GeminiAccumulator::new()
  acc.feed({
    event: "data",
    data: {
      "candidates": [
        {
          "content": {
            "role": "model",
            "parts": [
              { "text": "Preface" },
              {
                "functionCall": { "name": "lookup", "args": { "q": "moonbit" } },
              },
            ],
          },
        },
      ],
    },
  })

  match acc.finish() {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "lookup")
      assert_eq(rich.content, "Preface")
    }
    _ => fail("Expected tool calls with content")
  }

  let bad_args = StringBuilder::new()
  bad_args.write_string("{")
  let invalid_acc : GeminiAccumulator = {
    text: StringBuilder::new(),
    tool_calls: [{ id: "call_1", name: "lookup", arguments: bad_args }],
    finished: false,
  }
  match invalid_acc.finish() {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].name, "lookup")
      assert_eq(calls[0].arguments, {})
    }
    _ => fail("Expected tool calls fallback")
  }
}

///|
test "accumulate_gemini consumes SSE text body" {
  let body =
    #|data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}
    #|
  match accumulate_gemini(body) {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello")
    _ => fail("Expected accumulated Gemini text")
  }
}
