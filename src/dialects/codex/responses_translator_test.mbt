///|
/// Tests for Codex -> Responses translator

///|
test "CodexToResponsesTranslator streams text deltas into Responses events" {
  let translator = CodexToResponsesTranslator::new(
    response_id="resp_codex",
    model="codex",
  )
  let delta_events = translator.translate({
    event: "message",
    data: {
      "method": "item/agentMessage/delta",
      "params": { "delta": "Hello" },
    },
  })
  assert_eq(delta_events[0].0, "response.created")
  assert_eq(delta_events[1].0, "response.in_progress")
  assert_eq(delta_events[2].0, "response.output_item.added")
  assert_eq(delta_events[3].0, "response.content_part.added")
  assert_eq(delta_events[4].0, "response.output_text.delta")

  let done_events = translator.translate({
    event: "message",
    data: {
      "method": "turn/completed",
      "params": { "turn": { "status": "completed" } },
    },
  })
  assert_eq(done_events[0].0, "response.output_text.done")
  assert_eq(done_events[1].0, "response.content_part.done")
  assert_eq(done_events[2].0, "response.output_item.done")
  assert_eq(done_events[3].0, "response.completed")
}

///|
test "CodexToResponsesTranslator turns failed turn into failed response.completed" {
  let translator = CodexToResponsesTranslator::new(response_id="resp_fail")
  let events = translator.translate({
    event: "message",
    data: {
      "method": "turn/completed",
      "params": { "turn": { "status": "failed", "error": "tool crashed" } },
    },
  })
  assert_eq(events.length(), 3)
  assert_eq(events[0].0, "response.created")
  assert_eq(events[1].0, "response.in_progress")
  assert_eq(events[2].0, "response.completed")
  match events[2].1 {
    {
      "response": {
        "status": String("failed"),
        "error": { "message": String(message), .. },
        ..
      },
      ..
    } => assert_eq(message, "tool crashed")
    _ => fail("Expected failed response payload")
  }
}

///|
test "CodexToResponsesTranslator accepts documented metadata no-op events" {
  let translator = CodexToResponsesTranslator::new(response_id="resp_meta")
  let events = translator.translate({
    event: "message",
    data: { "method": "thread/started", "params": {} },
  })
  assert_eq(events.map(fn(pair) { pair.0 }), [
    "response.created", "response.in_progress",
  ])
}
