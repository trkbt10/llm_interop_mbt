///|
/// Tests for HarmonyToResponsesTranslator SSE output structure
/// Verifies Responses API SSE event data fields match specification

///|
test "translator: response.created has response.id" {
  let translator = HarmonyToResponsesTranslator::new(
    response_id="resp_test_123",
  )
  let event : @sse.SseEvent = {
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": { "role": "assistant", "content": "" } },
      ]),
    },
  }
  let events = translator.translate(event)
  let created = events[0]
  assert_eq(created.0, "response.created")
  match created.1 {
    {
      "type": String("response.created"),
      "response": { "id": String(id), .. },
      ..
    } => assert_eq(id, "resp_test_123")
    _ => fail("response.created missing response.id")
  }
}

///|
test "translator: output_text.delta has required fields" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_001")
  // Init
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    }),
  )
  // Content delta
  let events = translator.translate({
    event: "",
    data: {
      "choices": Json::array([{ "index": 0, "delta": { "content": "Hello" } }]),
    },
  })
  // Find delta event (after output_item.added and content_part.added)
  let delta = events
    .iter()
    .find_first(fn(e) { e.0 == "response.output_text.delta" })
  match delta {
    Some((_, data)) =>
      match data {
        {
          "type": String("response.output_text.delta"),
          "delta": String(d),
          "content_index": Number(ci, ..),
          "output_index": Number(oi, ..),
          ..
        } => {
          assert_eq(d, "Hello")
          assert_eq(ci.to_int(), 0)
          assert_eq(oi.to_int(), 0)
        }
        _ => fail("output_text.delta missing required fields")
      }
    None => fail("No output_text.delta event emitted")
  }
}

///|
test "translator: function_call output_item.added has correct structure" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_001")
  // Init
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    }),
  )
  // Tool call
  let events = translator.translate({
    event: "",
    data: {
      "choices": Json::array([
        {
          "index": 0,
          "delta": {
            "tool_calls": Json::array([
              {
                "id": "call_abc",
                "type": "function",
                "function": { "name": "shell", "arguments": "{\"cmd\":\"ls\"}" },
              },
            ]),
          },
        },
      ]),
    },
  })
  // output_item.added for function_call
  let added = events
    .iter()
    .find_first(fn(e) { e.0 == "response.output_item.added" })
  match added {
    Some((_, data)) =>
      match data {
        {
          "output_index": Number(oi, ..),
          "item": {
            "type": String("function_call"),
            "name": String(name),
            "call_id": String(cid),
            "status": String("in_progress"),
            ..
          },
          ..
        } => {
          assert_eq(oi.to_int(), 0)
          assert_eq(name, "shell")
          assert_eq(cid, "call_abc")
        }
        _ => fail("function_call item has wrong structure")
      }
    None => fail("No output_item.added event")
  }
}

///|
test "translator: response.completed emitted on stop" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_001")
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "Hi" } },
        ]),
      },
    }),
  )
  let events = translator.translate({
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "stop" },
      ]),
    },
  })
  let completed = events
    .iter()
    .find_first(fn(e) { e.0 == "response.completed" })
  assert_true(not(completed is None))
}

///|
test "translator: response.completed emitted on tool_calls finish" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_001")
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    }),
  )
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          {
            "index": 0,
            "delta": {
              "tool_calls": Json::array([
                {
                  "id": "fc_1",
                  "type": "function",
                  "function": { "name": "ls", "arguments": "{}" },
                },
              ]),
            },
          },
        ]),
      },
    }),
  )
  let events = translator.translate({
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "tool_calls" },
      ]),
    },
  })
  let completed = events
    .iter()
    .find_first(fn(e) { e.0 == "response.completed" })
  assert_true(not(completed is None))
}

///|
test "translator: multiple content deltas accumulate" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_001")
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    }),
  )
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "content": "Hello " } },
        ]),
      },
    }),
  )
  ignore(
    translator.translate({
      event: "",
      data: {
        "choices": Json::array([{ "index": 0, "delta": { "content": "world" } }]),
      },
    }),
  )
  let events = translator.translate({
    event: "",
    data: {
      "choices": Json::array([
        { "index": 0, "delta": {}, "finish_reason": "stop" },
      ]),
    },
  })
  // output_text.done should have the full accumulated text
  let done = events
    .iter()
    .find_first(fn(e) { e.0 == "response.output_text.done" })
  match done {
    Some((_, data)) =>
      match data {
        { "text": String(t), .. } => assert_eq(t, "Hello world")
        _ => fail("output_text.done missing text")
      }
    None => fail("No output_text.done event")
  }
}

///|
test "translator: text stream emits final text completion events" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_rt")
  let all_events : Array[@sse.SseEvent] = []
  let chunks : Array[@sse.SseEvent] = [
    {
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    },
    {
      event: "",
      data: {
        "choices": Json::array([{ "index": 0, "delta": { "content": "Four" } }]),
      },
    },
    {
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": {}, "finish_reason": "stop" },
        ]),
      },
    },
  ]
  for chunk in chunks {
    for translated in translator.translate(chunk) {
      all_events.push({ event: translated.0, data: translated.1 })
    }
  }
  let text_done = all_events
    .iter()
    .find_first(fn(event) { event.event == "response.output_text.done" })
  match text_done {
    Some({ data: { "text": String(text), .. }, .. }) => assert_eq(text, "Four")
    None => fail("Expected output_text.done")
    _ => fail("Expected completed text event")
  }
  let completed = all_events
    .iter()
    .find_first(fn(event) { event.event == "response.completed" })
  assert_true(not(completed is None))
}

///|
test "translator: tool call stream emits completed function call item" {
  let translator = HarmonyToResponsesTranslator::new(response_id="resp_tc")
  let all_events : Array[@sse.SseEvent] = []
  let chunks : Array[@sse.SseEvent] = [
    {
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": { "role": "assistant", "content": "" } },
        ]),
      },
    },
    {
      event: "",
      data: {
        "choices": Json::array([
          {
            "index": 0,
            "delta": {
              "tool_calls": Json::array([
                {
                  "index": 0,
                  "id": "call_test",
                  "type": "function",
                  "function": {
                    "name": "get_weather",
                    "arguments": "{\"city\":",
                  },
                },
              ]),
            },
          },
        ]),
      },
    },
    {
      event: "",
      data: {
        "choices": Json::array([
          {
            "index": 0,
            "delta": {
              "tool_calls": Json::array([
                {
                  "index": 0,
                  "type": "function",
                  "function": { "arguments": "\"Tokyo\"}" },
                },
              ]),
            },
          },
        ]),
      },
    },
    {
      event: "",
      data: {
        "choices": Json::array([
          { "index": 0, "delta": {}, "finish_reason": "tool_calls" },
        ]),
      },
    },
  ]
  for chunk in chunks {
    for translated in translator.translate(chunk) {
      all_events.push({ event: translated.0, data: translated.1 })
    }
  }
  let done = all_events
    .iter()
    .find_first(fn(event) {
      match event {
        {
          event: "response.output_item.done",
          data: {
            "item": {
              "type": String("function_call"),
              "name": String("get_weather"),
              ..
            },
            ..
          },
        } => true
        _ => false
      }
    })
  match done {
    Some(
      {
        data: {
          "item": {
            "id": String(id),
            "call_id": String(call_id),
            "name": String(name),
            "arguments": String(arguments),
            "status": String(status),
            ..
          },
          ..
        },
        ..,
      }
    ) => {
      assert_eq(id, "call_test")
      assert_eq(call_id, "call_test")
      assert_eq(name, "get_weather")
      assert_eq(arguments, "{\"city\":\"Tokyo\"}")
      assert_eq(status, "completed")
    }
    None => fail("Expected completed function_call item")
    _ => fail("Expected completed function_call payload")
  }
}
