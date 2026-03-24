///|
/// Whitebox coverage for Gemini SSE translator lifecycle and close helpers

///|
test "translator emits lifecycle, opens message once, and closes on stop" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_text",
    model="gemini-2.0-flash",
  )
  let text_event : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": Json::array([
        {
          "content": {
            "role": "model",
            "parts": Json::array([{ "text": "Hello" }]),
          },
        },
      ]),
    },
  }
  let text_events = translator.translate(text_event)
  assert_eq(text_events.length(), 5)
  assert_eq(text_events[0].0, "response.created")
  assert_eq(text_events[1].0, "response.in_progress")
  assert_eq(text_events[2].0, "response.output_item.added")
  assert_eq(text_events[3].0, "response.content_part.added")
  assert_eq(text_events[4].0, "response.output_text.delta")
  assert_true(translator.has_open_message)
  assert_eq(translator.current_message_text, "Hello")

  let noop_events : Array[(String, Json)] = []
  translator.ensure_message_started(noop_events)
  assert_eq(noop_events.length(), 0)

  let stop_event : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": Json::array([
        {
          "finishReason": "STOP",
          "content": { "role": "model", "parts": Json::array([]) },
        },
      ]),
    },
  }
  let stop_events = translator.translate(stop_event)
  assert_eq(stop_events.length(), 3)
  assert_eq(stop_events[0].0, "response.output_text.done")
  assert_eq(stop_events[1].0, "response.output_item.done")
  assert_eq(stop_events[2].0, "response.completed")
  assert_false(translator.has_open_message)
  assert_eq(translator.completed_output.length(), 1)
  match stop_events[2].1 {
    {
      "response": {
        "status": String("completed"),
        "model": String("gemini-2.0-flash"),
        "output": Array(output),
        ..
      },
      ..
    } => assert_eq(output.length(), 1)
    _ => fail("Expected completed Gemini response")
  }
}

///|
test "translator closes tool calls and completed event retains output" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_tools",
    model="gemini-2.0-flash",
  )
  let args = StringBuilder::new()
  args.write_string("{\"q\":\"moonbit\"}")
  translator.tool_calls.push({
    output_index: 3,
    call_id: "call_1",
    name: "lookup",
    arguments: args,
    completed: false,
  })

  let events : Array[(String, Json)] = []
  translator.close_tool_calls(events)
  assert_eq(events.length(), 2)
  assert_eq(events[0].0, "response.function_call_arguments.done")
  assert_eq(events[1].0, "response.output_item.done")
  assert_eq(translator.completed_output.length(), 1)
  assert_true(translator.tool_calls[0].completed)

  let completed = translator.build_completed_event()
  match completed {
    {
      "response": {
        "id": String("resp_tools"),
        "status": String("completed"),
        "model": String("gemini-2.0-flash"),
        "output": Array(output),
        ..
      },
      ..
    } => assert_eq(output.length(), 1)
    _ => fail("Expected completed event with tool output")
  }
}

///|
test "translator handles tool-call stream and max-tokens completion" {
  let translator = GeminiToResponsesTranslator::new(response_id="resp_max")
  let tool_event : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": Json::array([
        {
          "content": {
            "role": "model",
            "parts": Json::array([
              {
                "functionCall": { "name": "lookup", "args": { "q": "moonbit" } },
              },
            ]),
          },
        },
      ]),
    },
  }
  let tool_events = translator.translate(tool_event)
  assert_eq(tool_events.length(), 4)
  assert_eq(tool_events[0].0, "response.created")
  assert_eq(tool_events[1].0, "response.in_progress")
  assert_eq(tool_events[2].0, "response.output_item.added")
  assert_eq(tool_events[3].0, "response.function_call_arguments.delta")
  assert_eq(translator.tool_calls.length(), 1)

  let finish_event : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": Json::array([
        {
          "finishReason": "MAX_TOKENS",
          "content": { "role": "model", "parts": Json::array([]) },
        },
      ]),
    },
  }
  let finish_events = translator.translate(finish_event)
  assert_eq(finish_events.length(), 3)
  assert_eq(finish_events[0].0, "response.function_call_arguments.done")
  assert_eq(finish_events[1].0, "response.output_item.done")
  assert_eq(finish_events[2].0, "response.completed")
}

///|
test "translator preserves structured JSON text fragments exactly" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_json",
    model="gemini-2.0-flash",
  )
  let first : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        {
          "content": { "role": "model", "parts": [{ "text": "{\"answer\":" }] },
        },
      ],
    },
  }
  let second : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        {
          "content": {
            "role": "model",
            "parts": [{ "text": "{\"url\":\"https://example.com\"}}" }],
          },
        },
      ],
    },
  }
  let stop : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        { "finishReason": "STOP", "content": { "role": "model", "parts": [] } },
      ],
    },
  }
  let first_events = translator.translate(first)
  let second_events = translator.translate(second)
  let stop_events = translator.translate(stop)
  assert_eq(first_events[4].0, "response.output_text.delta")
  assert_eq(second_events[0].0, "response.output_text.delta")
  match stop_events[0].1 {
    { "text": String(text), .. } =>
      assert_eq(text, "{\"answer\":{\"url\":\"https://example.com\"}}")
    _ => fail("Expected output_text.done payload")
  }
}

///|
test "translator preserves invalid structured JSON text without validation" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_invalid_json",
    model="gemini-2.0-flash",
  )
  let first : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        {
          "content": { "role": "model", "parts": [{ "text": "{\"answer\":" }] },
        },
      ],
    },
  }
  let second : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        { "content": { "role": "model", "parts": [{ "text": "oops}" }] } },
      ],
    },
  }
  let stop : @sse.SseEvent = {
    event: "data",
    data: {
      "candidates": [
        { "finishReason": "STOP", "content": { "role": "model", "parts": [] } },
      ],
    },
  }
  ignore(translator.translate(first))
  ignore(translator.translate(second))
  let stop_events = translator.translate(stop)
  match stop_events[0].1 {
    { "text": String(text), .. } => assert_eq(text, "{\"answer\":oops}")
    _ => fail("Expected output_text.done payload")
  }
}

///|
test "translator canonicalizes final Gemini structured output text" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_structured",
    model="gemini-2.0-flash",
  )
  let events = translator.translate({
    event: "data",
    data: {
      "candidates": [
        {
          "content": {
            "parts": [
              {
                "text": "```json\n{\"lookup_verification_url_response\":{\"content\":\"{\\\"url\\\":\\\"https://example.com/stream\\\"}\"}}\n```",
              },
            ],
            "role": "model",
          },
          "finishReason": "STOP",
        },
      ],
    },
  })
  let done = events[5]
  assert_eq(done.0, "response.output_text.done")
  match done.1 {
    { "text": String(text), .. } =>
      assert_eq(text, "{\"url\":\"https://example.com/stream\"}")
    _ => fail("Expected normalized output_text.done")
  }
  let item_done = events[6]
  assert_eq(item_done.0, "response.output_item.done")
  match item_done.1 {
    {
      "item": {
        "content": [{ "type": "output_text", "text": String(text), .. }],
        ..
      },
      ..
    } => assert_eq(text, "{\"url\":\"https://example.com/stream\"}")
    _ => fail("Expected normalized output_item.done")
  }
}

///|
test "translator preserves Gemini grounding annotations on completed message" {
  let translator = GeminiToResponsesTranslator::new(
    response_id="resp_grounded",
    model="gemini-2.0-flash",
  )
  let events = translator.translate({
    event: "data",
    data: {
      "candidates": [
        {
          "content": {
            "parts": [{ "text": "Weather details" }],
            "role": "model",
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
          "finishReason": "STOP",
        },
      ],
    },
  })
  let annotation_events : Array[(String, Json)] = []
  for event in events {
    match event {
      ("response.output_text.annotation.added", _) =>
        annotation_events.push(event)
      _ => ()
    }
  }
  assert_eq(annotation_events.length(), 1)
  match annotation_events[0].1 {
    {
      "annotation": { "type": String("url_citation"), "url": String(url), .. },
      ..
    } => assert_eq(url, "https://example.com/weather")
    _ => fail("Expected annotation event")
  }
  match events[7].1 {
    {
      "item": {
        "content": [
          {
            "type": String("output_text"),
            "annotations": Array(annotations),
            ..
          },
        ],
        ..
      },
      ..
    } => {
      assert_eq(annotations.length(), 1)
      match annotations[0] {
        { "type": String("url_citation"), "title": String(title), .. } =>
          assert_eq(title, "Weather Source")
        _ => fail("Expected grounded output_text annotation")
      }
    }
    _ => fail("Expected grounded output_item.done")
  }
}
