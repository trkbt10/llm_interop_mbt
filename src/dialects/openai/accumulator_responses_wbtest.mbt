///|
/// Whitebox coverage for Responses API accumulator validation branches

///|
test "feed handles no-op events and unknown output items" {
  let acc = ResponsesApiAccumulator::new()
  acc.feed({ event: "response.created", data: {} })
  acc.feed({ event: "response.output_text.delta", data: {} })
  acc.feed({ event: "response.refusal.delta", data: {} })
  acc.feed({ event: "response.refusal.done", data: {} })
  acc.feed({ event: "response.output_text.annotation.added", data: {} })
  acc.feed({ event: "response.function_call_arguments.delta", data: {} })
  acc.feed({ event: "response.web_search_call.in_progress", data: {} })
  acc.feed({ event: "response.web_search_call.searching", data: {} })
  acc.feed({ event: "response.web_search_call.completed", data: {} })
  acc.feed({ event: "response.reasoning_summary_text.done", data: {} })
  acc.feed({ event: "response.output_text.done", data: {} })
  acc.feed({
    event: "response.output_item.done",
    data: { "item": { "type": "unknown_item" } },
  })
  match acc.finish() {
    @types.ModelResponse::Text(text) => assert_eq(text, "")
    _ => fail("Expected empty text response")
  }
}

///|
test "panic feed rejects function_call added snapshots without ids" {
  let anonymous_added = ResponsesApiAccumulator::new()
  anonymous_added.feed({
    event: "response.output_item.added",
    data: {
      "item": { "type": "function_call", "name": "lookup" },
      "output_index": 9,
    },
  })
}

///|
test "feed handles function call snapshots and output-index reconciliation" {
  let existing = ResponsesApiAccumulator::new()
  existing.feed({
    event: "response.output_item.added",
    data: {
      "item": {
        "type": "function_call",
        "id": "call_existing",
        "name": "lookup",
      },
      "output_index": 0,
    },
  })
  existing.feed({
    event: "response.output_item.done",
    data: {
      "item": {
        "type": "function_call",
        "id": "call_existing",
        "name": "lookup",
        "arguments": "{\"q\":\"moonbit\"}",
      },
      "output_index": 0,
    },
  })
  match existing.finish() {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "call_existing")
      assert_eq(calls[0].name, "lookup")
    }
    _ => fail("Expected ToolCalls from existing call")
  }

  let late = ResponsesApiAccumulator::new()
  late.feed({
    event: "response.output_item.done",
    data: {
      "item": {
        "type": "function_call",
        "id": "call_late",
        "name": "search",
        "arguments": "{\"q\":\"moonbit\"}",
      },
      "output_index": 3,
    },
  })
  match late.finish() {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "call_late")
      assert_eq(calls[0].name, "search")
    }
    _ => fail("Expected late ToolCalls response")
  }

  let no_index = ResponsesApiAccumulator::new()
  no_index.feed({
    event: "response.output_item.done",
    data: {
      "item": {
        "type": "function_call",
        "id": "call_no_index",
        "name": "search",
        "arguments": "{\"q\":\"moonbit\"}",
      },
    },
  })
  match no_index.finish() {
    @types.ModelResponse::ToolCalls(calls) => {
      assert_eq(calls.length(), 1)
      assert_eq(calls[0].id, "call_no_index")
      assert_eq(calls[0].name, "search")
    }
    _ => fail("Expected tool call from self-contained done event")
  }
}

///|
test "panic feed rejects function_call done snapshots without ids" {
  let anonymous_done = ResponsesApiAccumulator::new()
  anonymous_done.feed({
    event: "response.output_item.done",
    data: {
      "item": {
        "type": "function_call",
        "name": "lookup",
        "arguments": "{\"q\":\"moonbit\"}",
      },
      "output_index": 2,
    },
  })
}

///|
test "finish adds streamed refusal when no refusal part exists" {
  let acc = ResponsesApiAccumulator::new()
  acc.content_parts.push(@types.ResponseContentPart::OutputText("Prelude"))
  acc.refusal.write_string("Denied")
  match acc.finish() {
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) => {
          assert_eq(parts.length(), 2)
          match parts[1] {
            @types.ResponseContentPart::Refusal(reason) =>
              assert_eq(reason, "Denied")
            _ => fail("Expected appended refusal part")
          }
        }
        None => fail("Expected refusal content parts")
      }
    _ => fail("Expected RichText refusal result")
  }
}

///|
test "finish returns ToolCallsWithContent when tool calls and rich content coexist" {
  let acc = ResponsesApiAccumulator::new()
  let args = StringBuilder::new()
  args.write_string("{\"q\":\"moonbit\"}")
  acc.function_calls.push({ id: "call_1", name: "lookup", arguments: args })
  acc.content_parts.push(@types.ResponseContentPart::OutputText("Checking"))

  match acc.finish() {
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) => {
      assert_eq(tool_calls.length(), 1)
      assert_eq(tool_calls[0].name, "lookup")
      assert_eq(rich.content, "Checking")
    }
    _ => fail("Expected ToolCallsWithContent response")
  }
}

///|
test "panic feed rejects web search snapshots without ids" {
  let missing_id = ResponsesApiAccumulator::new()
  missing_id.feed({
    event: "response.output_item.added",
    data: { "item": { "type": "web_search_call" } },
  })
}

///|
test "feed handles web search completed status" {
  let completed = ResponsesApiAccumulator::new()
  completed.feed({
    event: "response.output_item.done",
    data: {
      "item": {
        "type": "web_search_call",
        "id": "ws_1",
        "status": "completed",
        "action": {
          "type": "search",
          "queries": Json::array([Json::string("moonbit")]),
        },
      },
      "output_index": 0,
    },
  })
  match completed.finish() {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.tool_traces.length(), 1)
      assert_eq(rich.tool_traces[0].statuses.length(), 1)
      match rich.tool_traces[0].arguments {
        { "queries": Array(queries), .. } => assert_eq(queries.length(), 1)
        _ => fail("Expected stored queries")
      }
    }
    _ => fail("Expected completed web search trace")
  }
}
