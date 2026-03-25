///|
/// Whitebox coverage for Codex chat request/response helper branches

///|
test "request helpers cover text-only prompt extraction and fallback model" {
  assert_eq(
    build_prompt_from_messages([
      { "role": "assistant", "content": "Ignored" },
      { "role": "system", "content": "System only" },
    ]),
    "System only",
  )
  assert_eq(
    build_prompt_from_messages([
      {
        "role": "user",
        "content": Json::array([
          { "type": "text", "text": "Alpha" },
          { "type": "text", "text": "Beta" },
        ]),
      },
    ]),
    "Alpha\nBeta",
  )

  let fallback_body =
    #|{"messages":[{"role":"user","content":[{"type":"text","text":"Alpha"},{"type":"text","text":"Beta"}]}]}
  let fallback_model = chat_request_to_protocol(
    fallback_body,
    @types.TransformContext::default(),
  )
  let fallback_json = @json.parse(fallback_model) catch {
    _ => fail("Expected fallback model json")
  }
  match fallback_json {
    { "prompt": String(prompt), "model": String(model), .. } => {
      assert_eq(prompt, "Alpha\nBeta")
      assert_eq(model, "codex")
    }
    _ => fail("Expected prompt and fallback model")
  }
}

///|
test "panic request helpers reject multimodal and non-message passthrough fallbacks" {
  ignore(
    build_prompt_from_messages([
      { "role": "system", "content": "System rules" },
      {
        "role": "user",
        "content": Json::array([
          {
            "type": "image_url",
            "image_url": { "url": "https://example.com/a.png" },
          },
          { "type": "text", "text": "First" },
        ]),
      },
    ]),
  )
  let body_without_messages =
    #|{"model":"codex","input":"hello"}
  ignore(
    chat_request_to_protocol(
      body_without_messages,
      @types.TransformContext::default(),
    ),
  )
  let body_with_non_array_messages =
    #|{"model":"codex","messages":"hello"}
  ignore(
    chat_request_to_protocol(
      body_with_non_array_messages,
      @types.TransformContext::default(),
    ),
  )
}

///|
test "event processing covers fallbacks, token precedence, and ignored branches" {
  let acc = EventAccumulator::new()
  process_event(acc, { "params": { "delta": "missing method" } })
  assert_eq(acc.content, "")

  process_event(acc, {
    "method": "item/agentMessage/delta",
    "params": { "delta": "Hello" },
  })
  process_event(acc, {
    "method": "codex/event/agent_message_content_delta",
    "params": { "delta": "duplicate" },
  })
  process_event(acc, {
    "method": "codex/event/agent_message",
    "params": { "msg": { "message": "ignored fallback" } },
  })
  process_event(acc, {
    "method": "codex/event/task_complete",
    "params": { "msg": { "last_agent_message": "ignored complete" } },
  })
  assert_eq(acc.content, "Hello")

  process_event(acc, {
    "method": "thread/started",
    "params": { "thread": { "id": "thread_1" } },
  })
  assert_eq(acc.thread_id, "thread_1")

  process_event(acc, {
    "method": "thread/tokenUsage/updated",
    "params": {
      "tokenUsage": {
        "inputTokens": 9,
        "outputTokens": 4,
        "totalTokens": 13,
        "cachedInputTokens": 2,
        "reasoningOutputTokens": 1,
      },
    },
  })
  assert_eq(acc.total_tokens, 13)
  process_event(acc, {
    "method": "codex/event/token_count",
    "params": {
      "msg": {
        "info": {
          "total_token_usage": {
            "input_tokens": 100,
            "output_tokens": 50,
            "total_tokens": 150,
          },
        },
      },
    },
  })
  assert_eq(acc.total_tokens, 13)

  process_event(acc, {
    "method": "item/completed",
    "params": {
      "item": {
        "type": "reasoning",
        "summary": Json::array([{ "text": "First reason" }, "Second reason", 7]),
      },
    },
  })
  assert_eq(acc.reasoning_text, "First reason\nSecond reason")

  process_event(acc, {
    "method": "turn/completed",
    "params": {
      "turn": { "id": "turn_1", "status": "inProgress", "error": "boom" },
    },
  })
  assert_eq(acc.turn_id, "turn_1")
  assert_eq(acc.finish_reason, "length")
  assert_true(acc.has_error)
  assert_eq(acc.error_message, "boom")

  process_event(acc, {
    "method": "codex/event/task_started",
    "params": { "msg": { "model_context_window": 128000 } },
  })
  process_event(acc, { "method": "unknown/event", "params": {} })
  assert_eq(acc.thread_id, "thread_1")
}

///|
test "status and extraction helpers cover invalid token usage and non-summary items" {
  assert_eq(codex_status_to_finish_reason("completed"), "stop")
  assert_eq(codex_status_to_finish_reason("failed"), "stop")
  assert_eq(codex_status_to_finish_reason("interrupted"), "stop")
  assert_eq(codex_status_to_finish_reason("inProgress"), "length")
  assert_eq(codex_status_to_finish_reason("mystery"), "stop")

  let acc = EventAccumulator::new()
  extract_token_usage(acc, { "bad": true })
  assert_eq(acc.total_tokens, 0)

  apply_token_usage(acc, {
    input_tokens: 3,
    output_tokens: 4,
    total_tokens: 7,
    cached_input_tokens: 1,
    reasoning_output_tokens: 2,
  })
  assert_eq(acc.input_tokens, 3)
  assert_eq(acc.output_tokens, 4)
  assert_eq(acc.total_tokens, 7)
  assert_eq(acc.cached_input_tokens, 1)
  assert_eq(acc.reasoning_output_tokens, 2)

  extract_reasoning(acc, {
    "summary": Json::array(["Third reason", { "skip": true }]),
  })
  assert_eq(acc.reasoning_text, "Third reason")
  extract_reasoning(acc, {
    "summary": Json::array([{ "text": "Fourth reason" }]),
  })
  assert_eq(acc.reasoning_text, "Third reason\nFourth reason")
  extract_reasoning(acc, { "type": "reasoning" })
  assert_eq(acc.reasoning_text, "Third reason\nFourth reason")
}

///|
test "events_to_chat and process_event ignore malformed event shapes" {
  let malformed = @json.parse(events_to_chat("{\"not\":\"an array\"}")) catch {
    _ => fail("expected structured parse error")
  }
  match malformed {
    { "error": { "type": String(type_), .. }, .. } =>
      assert_eq(type_, "parse_error")
    _ => fail("expected codex parse error")
  }

  let acc = EventAccumulator::new()
  process_event(acc, { "method": "item/agentMessage/delta", "params": {} })
  process_event(acc, { "method": "codex/event/agent_message", "params": {} })
  process_event(acc, { "method": "codex/event/task_complete", "params": {} })
  process_event(acc, { "method": "turn/completed", "params": { "turn": {} } })
  process_event(acc, { "method": "thread/started", "params": { "thread": {} } })
  process_event(acc, { "method": "thread/tokenUsage/updated", "params": {} })
  process_event(acc, { "method": "codex/event/token_count", "params": {} })
  process_event(acc, {
    "method": "codex/event/token_count",
    "params": { "msg": {} },
  })
  process_event(acc, { "method": "codex/event/task_started", "params": {} })
  assert_eq(acc.content, "")
  assert_eq(acc.turn_id, "")
  assert_eq(acc.thread_id, "")
  assert_eq(acc.total_tokens, 0)
  assert_false(acc.has_error)
}

///|
test "response builder covers error, id fallbacks, tool calls, and usage extras" {
  let error_acc = EventAccumulator::new()
  error_acc.has_error = true
  error_acc.error_message = "turn failed"
  let error_json = @json.parse(build_openai_response(error_acc)) catch {
    _ => fail("Expected codex error json")
  }
  match error_json {
    { "error": { "message": String(message), "code": "turn_failed", .. }, .. } =>
      assert_eq(message, "turn failed")
    _ => fail("Expected codex error response")
  }

  let thread_acc = EventAccumulator::new()
  thread_acc.thread_id = "thread_only"
  thread_acc.content = "Answer"
  thread_acc.cached_input_tokens = 5
  thread_acc.reasoning_output_tokens = 6
  thread_acc.tool_calls.push({
    "id": "call_1",
    "type": "function",
    "function": { "name": "lookup", "arguments": "{\"q\":\"moonbit\"}" },
  })
  let thread_json = @json.parse(build_openai_response(thread_acc)) catch {
    _ => fail("Expected thread-id response json")
  }
  match thread_json {
    {
      "id": String(id),
      "choices": Array(
        [
          {
            "message": {
              "content": String(content),
              "tool_calls": Array(tool_calls),
              ..
            },
            ..
          },
        ]
      ),
      "usage": {
        "cached_tokens": Number(cached, ..),
        "reasoning_tokens": Number(reasoning, ..),
        ..
      },
      ..
    } => {
      assert_eq(id, "codex-thread_only")
      assert_eq(content, "Answer")
      assert_eq(tool_calls.length(), 1)
      assert_eq(cached.to_int(), 5)
      assert_eq(reasoning.to_int(), 6)
    }
    _ => fail("Expected thread-id response with tool calls")
  }

  let default_acc = EventAccumulator::new()
  default_acc.content = "Fallback"
  let default_json = @json.parse(build_openai_response(default_acc)) catch {
    _ => fail("Expected default-id response json")
  }
  match default_json {
    {
      "id": String(id),
      "choices": Array([{ "message": { "content": String(content), .. }, .. }]),
      ..
    } => {
      assert_eq(id, "codex-response")
      assert_eq(content, "Fallback")
    }
    _ => fail("Expected default-id response")
  }
}
