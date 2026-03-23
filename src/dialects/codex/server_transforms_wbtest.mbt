///|
/// Whitebox coverage for Codex server transform helpers and fallbacks

///|
test "chat response fallback covers empty content and derived total tokens" {
  let response =
    #|{"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call_1"}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":7,"completion_tokens":2}}
  let events = chat_response_to_events(response, "thread_1", "turn_1", "item_1")
  assert_eq(events.length(), 6)

  let delta_json = @json.parse(events[2]) catch {
    _ => fail("Expected delta json")
  }
  match delta_json {
    { "params": { "delta": String(delta), .. }, .. } => assert_eq(delta, "")
    _ => fail("Expected delta event")
  }

  let usage_json = @json.parse(events[4]) catch {
    _ => fail("Expected usage json")
  }
  match usage_json {
    {
      "params": {
        "tokenUsage": {
          "total": {
            "inputTokens": Number(input, ..),
            "outputTokens": Number(output, ..),
            "totalTokens": Number(total, ..),
            ..
          },
          ..
        },
        ..
      },
      ..
    } => {
      assert_eq(input.to_int(), 7)
      assert_eq(output.to_int(), 2)
      assert_eq(total.to_int(), 9)
    }
    _ => fail("Expected derived total tokens")
  }
}

///|
test "sse helpers cover content extraction and missing usage" {
  match
    sse_chunk_to_codex_delta(
      { "choices": Json::array([{ "delta": { "content": "Hello" } }]) },
      "item_1",
    ) {
    Some(event) => {
      let parsed = @json.parse(event) catch {
        _ => fail("Expected SSE delta json")
      }
      match parsed {
        {
          "method": String("item/agentMessage/delta"),
          "params": { "itemId": String("item_1"), "delta": String("Hello"), .. },
          ..
        } => ()
        _ => fail("Expected wrapped SSE delta")
      }
    }
    None => fail("Expected SSE delta event")
  }

  assert_eq(
    sse_chunk_to_codex_delta(
      { "choices": Json::array([{ "delta": { "content": "" } }]) },
      "item_1",
    ),
    None,
  )
  assert_eq(
    sse_chunk_to_codex_delta(
      { "choices": Json::array([{ "delta": {} }]) },
      "item_1",
    ),
    None,
  )

  assert_eq(
    sse_chunk_extract_usage({
      "usage": { "prompt_tokens": 3, "completion_tokens": 4, "total_tokens": 7 },
    }),
    Some((3, 4, 7)),
  )
  assert_eq(sse_chunk_extract_usage({ "usage": { "prompt_tokens": 3 } }), None)
}

///|
test "event builders cover success, failure, and private error sequence" {
  let turn_started = @json.parse(make_turn_started_event("turn_1")) catch {
    _ => fail("Expected turn started json")
  }
  match turn_started {
    {
      "method": String("turn/started"),
      "params": {
        "turn": { "id": String("turn_1"), "status": String("inProgress"), .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected turn started event")
  }

  let item_started = @json.parse(make_item_started_event("item_1")) catch {
    _ => fail("Expected item started json")
  }
  match item_started {
    {
      "method": String("item/started"),
      "params": {
        "item": { "id": String("item_1"), "text": String(""), .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected item started event")
  }

  let delta_event = @json.parse(make_agent_message_delta_event("item_1", "Hi")) catch {
    _ => fail("Expected agent delta json")
  }
  match delta_event {
    {
      "method": String("item/agentMessage/delta"),
      "params": { "itemId": String("item_1"), "delta": String("Hi"), .. },
      ..
    } => ()
    _ => fail("Expected agent delta event")
  }

  let item_completed = @json.parse(make_item_completed_event("item_1", "Done")) catch {
    _ => fail("Expected item completed json")
  }
  match item_completed {
    {
      "method": String("item/completed"),
      "params": {
        "item": { "id": String("item_1"), "text": String("Done"), .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected item completed event")
  }

  let token_usage = @json.parse(make_token_usage_event(1, 2, 3)) catch {
    _ => fail("Expected token usage json")
  }
  match token_usage {
    {
      "method": String("thread/tokenUsage/updated"),
      "params": {
        "tokenUsage": {
          "total": {
            "inputTokens": Number(input, ..),
            "outputTokens": Number(output, ..),
            "totalTokens": Number(total, ..),
            ..
          },
          ..
        },
        ..
      },
      ..
    } => {
      assert_eq(input.to_int(), 1)
      assert_eq(output.to_int(), 2)
      assert_eq(total.to_int(), 3)
    }
    _ => fail("Expected token usage event")
  }

  let turn_completed = @json.parse(
    make_turn_completed_event("turn_1", "item_1", "Done"),
  ) catch {
    _ => fail("Expected turn completed json")
  }
  match turn_completed {
    {
      "method": String("turn/completed"),
      "params": {
        "turn": {
          "id": String("turn_1"),
          "status": String("completed"),
          "items": Array(items),
          ..
        },
        ..
      },
      ..
    } => assert_eq(items.length(), 1)
    _ => fail("Expected turn completed event")
  }

  let turn_failed = @json.parse(make_turn_failed_event("turn_1", "boom")) catch {
    _ => fail("Expected turn failed json")
  }
  match turn_failed {
    {
      "method": String("turn/completed"),
      "params": {
        "turn": {
          "id": String("turn_1"),
          "status": String("failed"),
          "error": { "message": String("boom"), .. },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected turn failed event")
  }

  let error_events = make_error_events("thread_1", "turn_1", "parse failed")
  assert_eq(error_events.length(), 2)
  let error_completed = @json.parse(error_events[1]) catch {
    _ => fail("Expected private error event json")
  }
  match error_completed {
    {
      "params": {
        "turn": {
          "id": String("turn_1"),
          "status": String("failed"),
          "error": { "message": String("parse failed"), .. },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected private error event")
  }
}
