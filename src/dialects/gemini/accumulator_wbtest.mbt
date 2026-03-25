///|
/// Whitebox coverage for Gemini accumulator paths

///|
test "GeminiAccumulator accumulates text and ignores documented metadata-only chunks" {
  let acc = GeminiAccumulator::new()

  acc.feed({
    event: "data",
    data: { "usageMetadata": { "totalTokenCount": 1 } },
  })
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
}

///|
test "panic GeminiAccumulator rejects malformed stream chunks" {
  let acc = GeminiAccumulator::new()
  acc.feed({ event: "data", data: { "other": true } })
}

///|
test "GeminiAccumulator returns tool calls with content" {
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
}

///|
test "GeminiAccumulator preserves grounding annotations" {
  let acc = GeminiAccumulator::new()
  acc.feed({
    event: "data",
    data: {
      "candidates": [
        {
          "content": {
            "role": "model",
            "parts": [{ "text": "Weather details" }],
          },
          "groundingMetadata": {
            "groundingChunks": [
              {
                "web": {
                  "uri": "https://example.com/weather",
                  "title": "Weather Source",
                },
              },
            ],
            "groundingSupports": [
              {
                "groundingChunkIndices": [0],
                "segment": { "text": "Weather", "startIndex": 0, "endIndex": 7 },
              },
            ],
          },
        },
      ],
    },
  })

  match acc.finish() {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::GeminiGroundingCitation(
          chunk_index~,
          chunk~,
          support~,
          cited_text~,
          start_index~,
          end_index~
        ) => {
          assert_eq(chunk_index, 0)
          assert_eq(cited_text, "Weather")
          match chunk {
            { "web": { "uri": String(url), "title": String(title), .. }, .. } => {
              assert_eq(title, "Weather Source")
              assert_eq(url, "https://example.com/weather")
            }
            _ => fail("Expected preserved grounding chunk")
          }
          match support {
            { "groundingChunkIndices": [Number(index, ..)], .. } =>
              assert_eq(index.to_int(), 0)
            _ => fail("Expected preserved grounding support")
          }
          assert_eq(start_index, 0)
          assert_eq(end_index, 7)
        }
        _ => fail("Expected grounding annotation")
      }
    }
    _ => fail("Expected grounded RichText response")
  }
}

///|
test "panic GeminiAccumulator rejects malformed tool arguments" {
  let bad_args = StringBuilder::new()
  bad_args.write_string("{")
  let invalid_acc : GeminiAccumulator = {
    text: StringBuilder::new(),
    tool_calls: [{ id: "call_1", name: "lookup", arguments: bad_args }],
    annotations: [],
  }
  invalid_acc.finish() |> ignore
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
