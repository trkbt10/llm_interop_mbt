///|
/// OpenAI dialect accumulator tests

///|
fn read_sse_fixture(path : String) -> String raise {
  @utils.read_testdata(path)
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

///|
test "ChatCompletionsAccumulator preserves mixed text and tool calls" {
  let jsonl =
    #| {"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"content":"Let me check"},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{"tool_calls":[{"id":"fc_123","type":"function","function":{"name":"datetime","arguments":"{}"}}]},"finish_reason":null}]}
    #| {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
  let result = accumulate_chat_completions(jsonl)
  match result {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "datetime")
      assert_eq(rich.content, "Let me check")
    }
    _ => fail("Expected ToolCallsWithContent response")
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
    #| {"event":"response.output_text.annotation.added","data":{"type":"response.output_text.annotation.added","annotation":{"type":"web_search_result_location","cited_text":"Weather details","encrypted_index":"enc_tokyo","title":"Tokyo Weather","url":"https://example.com/tokyo","start_index":8,"end_index":15},"sequence_number":8}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":9}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 2)
      assert_eq(rich.tool_traces.length(), 1)
      assert_eq(rich.tool_traces[0].statuses.length(), 3)
      match rich.annotations[1] {
        @types.ResponseAnnotation::WebSearchResultCitation(title~, url~, ..) => {
          assert_eq(title, "Tokyo Weather")
          assert_eq(url, "https://example.com/tokyo")
        }
        _ => fail("Expected interop web-search citation")
      }
      match rich.tool_traces[0].arguments {
        { "query": String(query), .. } =>
          assert_eq(query, "current weather in Tokyo")
        _ => fail("Expected query")
      }
    }
    _ => fail("Expected RichText response")
  }
}

///|
test "ResponsesApiAccumulator refusal via output_item.done no double count" {
  // Simulates: refusal.delta events + output_item.done with refusal in content.
  // Both carry refusal text. Only one Refusal should appear in content_parts.
  // Ref: docs/upstream/openai-responses-create.md:13566-13581
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.refusal.delta","data":{"type":"response.refusal.delta","delta":"I cannot","sequence_number":1}}
    #| {"event":"response.refusal.delta","data":{"type":"response.refusal.delta","delta":" help.","sequence_number":2}}
    #| {"event":"response.output_item.done","data":{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","role":"assistant","content":[{"type":"refusal","refusal":"I cannot help."}]}}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":4}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          // Count refusal parts — should be exactly 1
          let mut refusal_count = 0
          for p in parts {
            match p {
              @types.ResponseContentPart::Refusal(_) =>
                refusal_count = refusal_count + 1
              _ => ()
            }
          }
          inspect(refusal_count, content="1")
        }
        None => fail("Expected content_parts with refusal")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "ResponsesApiAccumulator output_image via output_item.done no double count" {
  // content_part.added fires first, then output_item.done.
  // Only output_item.done should produce an OutputImage.
  // Ref: docs/upstream/openai-responses-create.md:13566-13581
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.content_part.added","data":{"type":"response.content_part.added","output_index":0,"content_index":0,"part":{"type":"output_image","image_url":"https://example.com/img.png"}}}
    #| {"event":"response.content_part.done","data":{"type":"response.content_part.done","output_index":0,"content_index":0,"part":{"type":"output_image","image_url":"https://example.com/img.png"}}}
    #| {"event":"response.output_item.done","data":{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","role":"assistant","content":[{"type":"output_image","image_url":"https://example.com/img.png"}]}}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":4}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          let mut image_count = 0
          for p in parts {
            match p {
              @types.ResponseContentPart::OutputImage(..) =>
                image_count = image_count + 1
              _ => ()
            }
          }
          inspect(image_count, content="1")
        }
        None => fail("Expected content_parts with image")
      }
    _ => fail("Expected RichText")
  }
}

///|
test "ResponsesApiAccumulator preserves output_text boundaries around output_image" {
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"before","sequence_number":1}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"after","sequence_number":2}}
    #| {"event":"response.output_item.done","data":{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"before","annotations":[]},{"type":"output_image","image_url":"https://example.com/generated.png"},{"type":"output_text","text":"after","annotations":[]}]}}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":4}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "beforeafter")
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 3)
          match parts[0] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "before")
            _ => fail("Expected leading OutputText")
          }
          match parts[1] {
            @types.ResponseContentPart::OutputImage(url~) =>
              assert_eq(url, "https://example.com/generated.png")
            _ => fail("Expected OutputImage")
          }
          match parts[2] {
            @types.ResponseContentPart::OutputText(text) =>
              assert_eq(text, "after")
            _ => fail("Expected trailing OutputText")
          }
        }
        None => fail("Expected content_parts")
      }
    }
    _ => fail("Expected RichText")
  }
}

///|
test "ResponsesApiAccumulator reasoning via output_item.done" {
  // Ref: docs/upstream/openai-responses-create.md — reasoning output item
  let jsonl =
    #| {"event":"response.created","data":{"type":"response.created","sequence_number":0}}
    #| {"event":"response.output_item.done","data":{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","summary":[{"type":"summary_text","text":"Let me analyze..."}]}}}
    #| {"event":"response.output_text.delta","data":{"type":"response.output_text.delta","delta":"The answer is 42.","sequence_number":2}}
    #| {"event":"response.completed","data":{"type":"response.completed","sequence_number":3}}
  let result = accumulate_responses_api(jsonl)
  match result {
    @types.ModelResponse::RichText(rich) => {
      inspect(rich.content, content="The answer is 42.")
      match rich.content_parts {
        Some(parts) => {
          let mut thinking_count = 0
          for p in parts {
            match p {
              @types.ResponseContentPart::Thinking(..) =>
                thinking_count = thinking_count + 1
              _ => ()
            }
          }
          inspect(thinking_count, content="1")
        }
        None => fail("Expected content_parts with thinking")
      }
    }
    _ => fail("Expected RichText")
  }
}
