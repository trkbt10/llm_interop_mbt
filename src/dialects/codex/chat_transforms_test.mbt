///|
/// Tests for Codex chat transforms

// =============================================================================
// Request transform tests
// =============================================================================

///|
test "chat_request_to_protocol: extracts last user message" {
  let body =
    #|{"model":"codex","messages":[{"role":"system","content":"You are helpful."},{"role":"user","content":"Say hello"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "prompt": String(prompt), "model": String(model), .. } => {
      // System + user messages combined
      assert_true(prompt.contains("Say hello"))
      assert_eq(model, "codex")
    }
    _ => fail("unexpected structure: " + result)
  }
}

///|
test "chat_request_to_protocol: single user message" {
  let body =
    #|{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "prompt": String(prompt), "model": String(model), .. } => {
      assert_eq(prompt, "hi")
      assert_eq(model, "gpt-4o")
    }
    _ => fail("unexpected structure")
  }
}

///|
test "chat_request_to_protocol: picks last user message from multi-turn" {
  let body =
    #|{"model":"codex","messages":[{"role":"user","content":"first"},{"role":"assistant","content":"ok"},{"role":"user","content":"second"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "prompt": String(prompt), .. } => assert_eq(prompt, "second")
    _ => fail("unexpected structure")
  }
}

///|
test "chat_request_to_protocol: system + user concatenated" {
  let body =
    #|{"model":"codex","messages":[{"role":"system","content":"Be concise"},{"role":"user","content":"Hello"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "prompt": String(prompt), .. } => {
      assert_true(prompt.contains("Be concise"))
      assert_true(prompt.contains("Hello"))
    }
    _ => fail("unexpected structure")
  }
}

///|
test "chat_request_to_protocol: preserves messages array" {
  let body =
    #|{"model":"codex","messages":[{"role":"user","content":"hi"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "messages": Array(msgs), .. } => assert_eq(msgs.length(), 1)
    _ => fail("messages array not preserved")
  }
}

///|
test "chat_request_to_protocol: extracts reasoning_effort" {
  let body =
    #|{"model":"o3-mini","messages":[{"role":"user","content":"hi"}],"reasoning_effort":"high"}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "model": String(model), "effort": String(effort), .. } => {
      assert_eq(model, "o3-mini")
      assert_eq(effort, "high")
    }
    _ => fail("unexpected structure: " + result)
  }
}

///|
test "chat_request_to_protocol: omits effort when not present" {
  let body =
    #|{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}]}
  let result = chat_request_to_protocol(body, @types.TransformContext::default())
  let s = result
  assert_true(not(s.contains("effort")))
}

///|
test "chat_request_to_protocol: handles invalid JSON gracefully" {
  let result = chat_request_to_protocol(
    "not json",
    @types.TransformContext::default(),
  )
  assert_eq(result, "not json")
}

// =============================================================================
// Fixture helper
// =============================================================================

///|
fn build_events_array_from_fixture() -> String raise {
  let lines = @utils.split_lines(
    @utils.read_testdata("testdata/codex/events.jsonl"),
  )
  let events : Array[Json] = []
  for line in lines {
    if line == "" {
      continue
    }
    events.push(@json.parse(line))
  }
  Json::array(events).stringify()
}

// =============================================================================
// Response transform tests: fixture-based
// =============================================================================

///|
test "events_to_chat: produces valid response from fixture" {
  let events_json = build_events_array_from_fixture() catch {
    err => fail("Failed to load fixture: " + err.to_string())
  }
  let result = events_to_chat(events_json)
  let json = @json.parse(result) catch { _ => fail("invalid json: " + result) }
  match json {
    {
      "id": String(id),
      "object": String(obj),
      "model": String(_),
      "choices": Array(choices),
      "usage": usage,
      ..
    } => {
      assert_true(id.has_prefix("codex-"))
      assert_eq(obj, "chat.completion")
      assert_eq(choices.length(), 1)
      match choices[0] {
        {
          "message": {
            "role": String("assistant"),
            "content": String(content),
            ..
          },
          "finish_reason": String(reason),
          ..
        } => {
          assert_eq(content, "Hello")
          assert_eq(reason, "stop")
        }
        _ => fail("unexpected choice structure")
      }
      match usage {
        {
          "prompt_tokens": Number(input, ..),
          "completion_tokens": Number(output, ..),
          "total_tokens": Number(total, ..),
          ..
        } => {
          assert_eq(input.to_int(), 12201)
          assert_eq(output.to_int(), 60)
          assert_eq(total.to_int(), 12261)
        }
        _ => fail("unexpected usage structure")
      }
    }
    _ => fail("unexpected response structure: " + result)
  }
}

///|
test "events_to_chat: extracts turn ID from fixture" {
  let events_json = build_events_array_from_fixture() catch {
    err => fail("Failed to load fixture: " + err.to_string())
  }
  let result = events_to_chat(events_json)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "id": String(id), .. } =>
      assert_eq(id, "codex-019cd785-1282-7d20-ab5f-c8cbb41113fd")
    _ => fail("no id field")
  }
}

///|
test "events_to_chat: includes cached and reasoning tokens" {
  let events_json = build_events_array_from_fixture() catch {
    err => fail("Failed to load fixture: " + err.to_string())
  }
  let result = events_to_chat(events_json)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    {
      "usage": {
        "cached_tokens": Number(cached, ..),
        "reasoning_tokens": Number(reasoning, ..),
        ..
      },
      ..
    } => {
      assert_eq(cached.to_int(), 5504)
      assert_eq(reasoning.to_int(), 53)
    }
    _ => fail("cached/reasoning tokens missing in usage")
  }
}

// =============================================================================
// Response transform tests: synthetic events
// =============================================================================

///|
test "events_to_chat: empty events produce empty content" {
  let result = events_to_chat("[]")
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(content), .. }, .. } =>
          assert_eq(content, "")
        _ => fail("unexpected choice structure")
      }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: assembles streaming deltas" {
  let events =
    #|[{"method":"item/agentMessage/delta","params":{"delta":"He"}},{"method":"item/agentMessage/delta","params":{"delta":"llo"}},{"method":"turn/completed","params":{"turn":{"id":"t1","status":"completed","error":null}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(content), .. }, .. } =>
          assert_eq(content, "Hello")
        _ => fail("unexpected choice structure")
      }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: falls back to agent_message when no deltas" {
  let events =
    #|[{"method":"codex/event/agent_message","params":{"msg":{"type":"agent_message","message":"World","phase":"final_answer"}}},{"method":"turn/completed","params":{"turn":{"id":"t2","status":"completed","error":null}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(content), .. }, .. } =>
          assert_eq(content, "World")
        _ => fail("unexpected choice")
      }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: falls back to task_complete last_agent_message" {
  let events =
    #|[{"method":"codex/event/task_complete","params":{"msg":{"type":"task_complete","turn_id":"t3","last_agent_message":"Fallback"}}},{"method":"turn/completed","params":{"turn":{"id":"t3","status":"completed","error":null}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "message": { "content": String(content), .. }, .. } =>
          assert_eq(content, "Fallback")
        _ => fail("unexpected choice")
      }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: handles codex/event/token_count format" {
  let events =
    #|[{"method":"codex/event/token_count","params":{"msg":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150,"cached_input_tokens":20,"reasoning_output_tokens":10}}}}},{"method":"turn/completed","params":{"turn":{"id":"t4","status":"completed","error":null}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    {
      "usage": {
        "prompt_tokens": Number(input, ..),
        "completion_tokens": Number(output, ..),
        "total_tokens": Number(total, ..),
        ..
      },
      ..
    } => {
      assert_eq(input.to_int(), 100)
      assert_eq(output.to_int(), 50)
      assert_eq(total.to_int(), 150)
    }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: interrupted turn maps to stop" {
  let events =
    #|[{"method":"turn/completed","params":{"turn":{"id":"t5","status":"interrupted","error":null}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "choices": Array(choices), .. } =>
      match choices[0] {
        { "finish_reason": String(reason), .. } => assert_eq(reason, "stop")
        _ => fail("unexpected choice")
      }
    _ => fail("unexpected structure")
  }
}

///|
test "events_to_chat: handles turn error" {
  let events =
    #|[{"method":"turn/completed","params":{"turn":{"id":"t6","status":"failed","error":"something went wrong"}}}]
  let result = events_to_chat(events)
  let json = @json.parse(result) catch { _ => fail("invalid json") }
  match json {
    { "error": { "message": String(msg), .. }, .. } =>
      assert_eq(msg, "something went wrong")
    _ => fail("expected error response: " + result)
  }
}

///|
test "events_to_chat: invalid JSON returns input" {
  assert_eq(events_to_chat("not json"), "not json")
}

///|
test "response_to_chat: is alias for events_to_chat" {
  let events_json = build_events_array_from_fixture() catch {
    err => fail("Failed to load fixture: " + err.to_string())
  }
  assert_eq(
    events_to_chat(events_json),
    response_to_chat(events_json),
  )
}

// =============================================================================
// Gateway tests
// =============================================================================

///|
test "CodexSession::new: creates uninitialized session" {
  let session = CodexSession::new("/tmp")
  assert_eq(session.phase, Uninitialized)
  assert_eq(session.thread_id, "")
  assert_eq(session.next_id, 1)
  assert_eq(session.cwd, "/tmp")
  assert_eq(session.approval_policy, "never")
  assert_eq(session.model, "codex")
}

///|
test "prepare_codex_upstream: fresh session produces 4 steps" {
  let session = CodexSession::new("/workspace")
  let body =
    #|{"prompt":"hello","model":"codex"}
  let req = prepare_codex_upstream(body, session)
  assert_eq(req.steps.length(), 4)
  assert_eq(req.steps[0].kind, Request) // initialize
  assert_eq(req.steps[1].kind, Notification) // initialized
  assert_eq(req.steps[2].kind, Request) // thread/start
  assert_eq(req.steps[3].kind, TurnStart) // turn/start
  assert_eq(req.next_session.phase, TurnInProgress)
  assert_eq(req.next_session.next_id, 4)
}

///|
test "prepare_codex_upstream: ready session produces 1 step" {
  let session : CodexSession = {
    phase: Ready,
    thread_id: "thread-123",
    next_id: 5,
    cwd: "/workspace",
    approval_policy: "never",
    model: "codex",
  }
  let body =
    #|{"prompt":"hello","model":"codex"}
  let req = prepare_codex_upstream(body, session)
  assert_eq(req.steps.length(), 1)
  assert_eq(req.steps[0].kind, TurnStart)
  assert_eq(req.next_session.next_id, 6)
}

///|
test "prepare_codex_upstream: extracts prompt from intermediate format" {
  let session : CodexSession = {
    phase: Ready,
    thread_id: "t1",
    next_id: 1,
    cwd: "/tmp",
    approval_policy: "never",
    model: "codex",
  }
  let body =
    #|{"prompt":"test prompt","model":"codex"}
  let req = prepare_codex_upstream(body, session)
  let msg = req.steps[0].message
  // The turn/start message should contain the prompt
  assert_true(msg.contains("test prompt"))
}

///|
test "update_session_from_thread_response: extracts thread_id" {
  let session = CodexSession::new("/tmp")
  let response : Json = {
    "id": 2,
    "result": { "thread": { "id": "thread-abc-123" } },
  }
  let updated = update_session_from_thread_response(session, response)
  assert_eq(updated.thread_id, "thread-abc-123")
  assert_eq(updated.phase, Ready)
}

///|
test "update_session_from_thread_response: ignores non-thread responses" {
  let session = CodexSession::new("/tmp")
  let response : Json = { "id": 1, "result": { "ok": true } }
  let updated = update_session_from_thread_response(session, response)
  assert_eq(updated.thread_id, "")
}

///|
test "patch_turn_start_thread_id: patches threadId in params" {
  let msg =
    #|{"id":3,"method":"turn/start","params":{"threadId":"","input":[]}}
  let patched = patch_turn_start_thread_id(msg, "thread-xyz")
  assert_true(patched.contains("thread-xyz"))
  assert_true(not(patched.contains("\"threadId\":\"\"")))
}

///|
test "prepare_codex_upstream: propagates model and effort to turn/start" {
  let session : CodexSession = {
    phase: Ready,
    thread_id: "t1",
    next_id: 1,
    cwd: "/tmp",
    approval_policy: "never",
    model: "codex",
  }
  let body =
    #|{"prompt":"hello","model":"o3-mini","effort":"high"}
  let req = prepare_codex_upstream(body, session)
  let msg = req.steps[0].message
  assert_true(msg.contains("o3-mini"))
  assert_true(msg.contains("high"))
  // Session model is updated
  assert_eq(req.next_session.model, "o3-mini")
}

///|
test "prepare_codex_upstream: full sequence includes model in thread/start" {
  let session = CodexSession::new("/workspace")
  let body =
    #|{"prompt":"hello","model":"gpt-4o"}
  let req = prepare_codex_upstream(body, session)
  assert_eq(req.steps.length(), 4)
  // thread/start (step 2) should contain model
  let thread_msg = req.steps[2].message
  assert_true(thread_msg.contains("gpt-4o"))
  // turn/start (step 3) should contain model
  let turn_msg = req.steps[3].message
  assert_true(turn_msg.contains("gpt-4o"))
}

///|
test "mark_session_turn_complete: transitions to Ready" {
  let session : CodexSession = {
    phase: TurnInProgress,
    thread_id: "t1",
    next_id: 5,
    cwd: "/tmp",
    approval_policy: "never",
    model: "codex",
  }
  let updated = mark_session_turn_complete(session)
  assert_eq(updated.phase, Ready)
  assert_eq(updated.thread_id, "t1")
  assert_eq(updated.next_id, 5)
}
