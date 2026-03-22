///|
/// Tests for server_transforms: OpenAI response → Codex events

// =============================================================================
// Fixture helpers
// =============================================================================

///|
fn read_app_server_fixture_lines(filename : String) -> Array[String] raise {
  @utils.split_lines(
    @utils.read_testdata("testdata/codex/app_server/" + filename),
  )
}

// =============================================================================
// Fixture-based tests: single turn streaming (captured from Groq)
// =============================================================================

///|
test "fixture: single turn stream has correct event sequence" {
  let lines = read_app_server_fixture_lines("single_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Collect event methods (skip RPC responses with "id")
  let methods : Array[String] = []
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      { "method": String(m), .. } => methods.push(m)
      _ => ()
    }
  }
  // Verify streaming event sequence: thread/started, turn/started, item/started,
  // item/agentMessage/delta (1+), item/completed, thread/tokenUsage/updated, turn/completed
  assert_true(methods.contains("thread/started"))
  assert_true(methods.contains("turn/started"))
  assert_true(methods.contains("item/started"))
  assert_true(methods.contains("item/agentMessage/delta"))
  assert_true(methods.contains("item/completed"))
  assert_true(methods.contains("thread/tokenUsage/updated"))
  assert_true(methods.contains("turn/completed"))
}

///|
test "fixture: single turn stream answer is correct" {
  let lines = read_app_server_fixture_lines("single_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find item/completed and check the answer
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      {
        "method": String("item/completed"),
        "params": { "item": { "text": String(text), .. }, .. },
        ..
      } => {
        assert_eq(text, "4")
        return
      }
      _ => ()
    }
  }
  fail("No item/completed event found")
}

///|
test "fixture: single turn stream has token usage" {
  let lines = read_app_server_fixture_lines("single_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
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
        assert_true(input.to_int() > 0)
        assert_true(output.to_int() > 0)
        assert_true(total.to_int() > 0)
        return
      }
      _ => ()
    }
  }
  fail("No token usage event found")
}

///|
test "fixture: single turn stream initialize response" {
  let lines = read_app_server_fixture_lines("single_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let json = @json.parse(lines[0]) catch { _ => fail("invalid json") }
  match json {
    {
      "result": {
        "protocolVersion": String(ver),
        "serverInfo": { "name": String(name), .. },
        ..
      },
      ..
    } => {
      assert_eq(ver, "2025-01-01")
      assert_eq(name, "llm_interop-app-server")
    }
    _ => fail("unexpected initialize response")
  }
}

// =============================================================================
// Fixture-based tests: multi-turn streaming (captured from Groq)
// =============================================================================

///|
test "fixture: multi-turn stream has two turns" {
  let lines = read_app_server_fixture_lines("multi_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let mut turn_completed_count = 0
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      { "method": String("turn/completed"), .. } =>
        turn_completed_count = turn_completed_count + 1
      _ => ()
    }
  }
  assert_eq(turn_completed_count, 2)
}

///|
test "fixture: multi-turn stream second turn recalls context" {
  let lines = read_app_server_fixture_lines("multi_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find the second item/completed (turn 2 response)
  let mut completed_count = 0
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      {
        "method": String("item/completed"),
        "params": { "item": { "text": String(text), .. }, .. },
        ..
      } => {
        completed_count = completed_count + 1
        if completed_count == 2 {
          // Second turn should contain "banana"
          assert_true(text.to_lower().contains("banana"))
          return
        }
      }
      _ => ()
    }
  }
  fail("Expected 2 item/completed events")
}

///|
test "fixture: multi-turn stream has streaming deltas" {
  let lines = read_app_server_fixture_lines("multi_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let mut delta_count = 0
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      { "method": String("item/agentMessage/delta"), .. } =>
        delta_count = delta_count + 1
      _ => ()
    }
  }
  // Should have multiple deltas (streaming)
  assert_true(delta_count > 1)
}

///|
test "fixture: multi-turn stream deltas reconstruct content" {
  let lines = read_app_server_fixture_lines("multi_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Reconstruct first turn content from deltas
  let content = StringBuilder::new()
  let mut in_first_turn = false
  let mut first_completed_text = ""
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      {
        "method": String("item/started"),
        "params": { "item": { "id": String("item_1"), .. }, .. },
        ..
      } => in_first_turn = true
      {
        "method": String("item/agentMessage/delta"),
        "params": { "itemId": String("item_1"), "delta": String(delta), .. },
        ..
      } => if in_first_turn { content.write_string(delta) }
      {
        "method": String("item/completed"),
        "params": {
          "item": { "id": String("item_1"), "text": String(text), .. },
          ..
        },
        ..
      } => {
        first_completed_text = text
        in_first_turn = false
      }
      _ => ()
    }
  }
  // Deltas should reconstruct the same content as item/completed
  assert_eq(content.to_string(), first_completed_text)
}

///|
test "fixture: multi-turn stream token usage increases" {
  let lines = read_app_server_fixture_lines("multi_turn_stream.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let totals : Array[Int] = []
  for line in lines {
    let json = @json.parse(line) catch { _ => continue }
    match json {
      {
        "method": String("thread/tokenUsage/updated"),
        "params": {
          "tokenUsage": {
            "total": { "totalTokens": Number(total, ..), .. },
            ..
          },
          ..
        },
        ..
      } => totals.push(total.to_int())
      _ => ()
    }
  }
  assert_eq(totals.length(), 2)
  // Second turn should use more tokens (includes conversation history)
  assert_true(totals[1] > totals[0])
}

// =============================================================================
// Synthetic tests
// =============================================================================

///|
test "chat_response_to_events: normal response produces 6 events" {
  let response =
    #|{"id":"chatcmpl-123","object":"chat.completion","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hello, world!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
  let events = chat_response_to_events(response, "thr_1", "turn_1", "item_1")
  assert_eq(events.length(), 6)
  // 1. turn/started
  let e0 = @json.parse(events[0]) catch { _ => fail("invalid json") }
  match e0 {
    {
      "method": String("turn/started"),
      "params": { "turn": { "status": String("inProgress"), .. }, .. },
      ..
    } => ()
    _ => fail("unexpected turn/started: " + events[0])
  }
  // 2. item/started
  let e1 = @json.parse(events[1]) catch { _ => fail("invalid json") }
  match e1 {
    {
      "method": String("item/started"),
      "params": {
        "item": { "type": String("agentMessage"), "id": String("item_1"), .. },
        ..
      },
      ..
    } => ()
    _ => fail("unexpected item/started: " + events[1])
  }
  // 3. item/agentMessage/delta
  let e2 = @json.parse(events[2]) catch { _ => fail("invalid json") }
  match e2 {
    {
      "method": String("item/agentMessage/delta"),
      "params": { "delta": String("Hello, world!"), .. },
      ..
    } => ()
    _ => fail("unexpected delta: " + events[2])
  }
  // 4. item/completed
  let e3 = @json.parse(events[3]) catch { _ => fail("invalid json") }
  match e3 {
    {
      "method": String("item/completed"),
      "params": { "item": { "text": String("Hello, world!"), .. }, .. },
      ..
    } => ()
    _ => fail("unexpected item/completed: " + events[3])
  }
  // 5. thread/tokenUsage/updated
  let e4 = @json.parse(events[4]) catch { _ => fail("invalid json") }
  match e4 {
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
      assert_eq(input.to_int(), 10)
      assert_eq(output.to_int(), 5)
      assert_eq(total.to_int(), 15)
    }
    _ => fail("unexpected tokenUsage: " + events[4])
  }
  // 6. turn/completed
  let e5 = @json.parse(events[5]) catch { _ => fail("invalid json") }
  match e5 {
    {
      "method": String("turn/completed"),
      "params": {
        "turn": { "status": String("completed"), "items": Array(items), .. },
        ..
      },
      ..
    } => assert_eq(items.length(), 1)
    _ => fail("unexpected turn/completed: " + events[5])
  }
}

///|
test "chat_response_to_events: error response produces 2 events" {
  let response =
    #|{"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}
  let events = chat_response_to_events(response, "thr_1", "turn_1", "item_1")
  assert_eq(events.length(), 2)
  // 1. turn/started
  let e0 = @json.parse(events[0]) catch { _ => fail("invalid json") }
  match e0 {
    {
      "method": String("turn/started"),
      "params": { "turn": { "status": String("inProgress"), .. }, .. },
      ..
    } => ()
    _ => fail("unexpected turn/started")
  }
  // 2. turn/completed with failed
  let e1 = @json.parse(events[1]) catch { _ => fail("invalid json") }
  match e1 {
    {
      "method": String("turn/completed"),
      "params": {
        "turn": {
          "status": String("failed"),
          "error": { "message": String(msg), .. },
          ..
        },
        ..
      },
      ..
    } => assert_eq(msg, "Rate limit exceeded")
    _ => fail("unexpected turn/completed: " + events[1])
  }
}

///|
test "chat_response_to_events: invalid JSON produces error events" {
  let events = chat_response_to_events("not json", "thr_1", "turn_1", "item_1")
  assert_eq(events.length(), 2)
  let e1 = @json.parse(events[1]) catch { _ => fail("invalid json") }
  match e1 {
    {
      "method": String("turn/completed"),
      "params": { "turn": { "status": String("failed"), .. }, .. },
      ..
    } => ()
    _ => fail("expected failed turn")
  }
}

///|
test "chat_response_to_events: token usage mapping" {
  let response =
    #|{"choices":[{"message":{"role":"assistant","content":"Hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}}
  let events = chat_response_to_events(response, "thr_1", "turn_1", "item_1")
  // Verify token usage event (index 4)
  let usage_event = @json.parse(events[4]) catch { _ => fail("invalid json") }
  match usage_event {
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
      assert_eq(input.to_int(), 100)
      assert_eq(output.to_int(), 50)
      assert_eq(total.to_int(), 150)
    }
    _ => fail("unexpected token usage")
  }
}

///|
test "chat_response_to_events: roundtrip with events_to_chat" {
  // Verify events produced by server_transforms can be consumed by chat_transforms
  let response =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Test roundtrip"},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":10,"total_tokens":30}}
  let events = chat_response_to_events(response, "thr_1", "turn_1", "item_1")
  // Parse events into a JSON array for events_to_chat
  let event_jsons : Array[Json] = []
  for e in events {
    event_jsons.push(@json.parse(e) catch { _ => Json::null() })
  }
  let events_array = Json::array(event_jsons).stringify()
  let result = events_to_chat(events_array)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    {
      "choices": [{ "message": { "content": String(content), .. }, .. }, ..],
      "usage": {
        "prompt_tokens": Number(pt, ..),
        "completion_tokens": Number(ct, ..),
        ..
      },
      ..
    } => {
      assert_eq(content, "Test roundtrip")
      assert_eq(pt.to_int(), 20)
      assert_eq(ct.to_int(), 10)
    }
    _ => fail("unexpected roundtrip result: " + result)
  }
}
