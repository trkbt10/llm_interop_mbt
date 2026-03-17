///|
/// Tests for Codex app-server protocol types
test "CodexRpcRequest::to_json" {
  let req = build_initialize_request(1, "test-client", "1.0.0")
  let json = req.to_json()
  match json {
    {
      "id": Number(id, ..),
      "method": String(m),
      "params": { "clientInfo": { "name": String(name), .. }, .. },
      ..
    } => {
      assert_eq(id.to_int(), 1)
      assert_eq(m, "initialize")
      assert_eq(name, "test-client")
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexRpcResponse::from_json result" {
  let json : Json = { "id": 1, "result": { "ok": true } }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_eq(r.error, None)
      match r.result {
        Some({ "ok": True, .. }) => ()
        _ => fail("Unexpected result")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "CodexRpcResponse::from_json error" {
  let json : Json = {
    "id": 2,
    "error": { "code": -32600, "message": "Invalid Request" },
  }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(2))
      assert_eq(r.result, None)
      match r.error {
        Some(e) => {
          assert_eq(e.code, -32600)
          assert_eq(e.message, "Invalid Request")
        }
        None => fail("Expected error")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "CodexThreadStartParams::to_json" {
  let params : CodexThreadStartParams = {
    cwd: "/workspace",
    approval_policy: "never",
    sandbox: Some(CodexSandboxConfig::none()),
    service_name: "test",
    personality: "pragmatic",
    experimental_raw_events: false,
    persist_extended_history: false,
    dynamic_tools: [],
  }
  let json = params.to_json()
  match json {
    { "cwd": String(cwd), "approvalPolicy": String(policy), .. } => {
      assert_eq(cwd, "/workspace")
      assert_eq(policy, "never")
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexInputItem::text" {
  let item = CodexInputItem::text("Hello, world!")
  let json = item.to_json()
  match json {
    { "type": String(t), "text": String(text), .. } => {
      assert_eq(t, "text")
      assert_eq(text, "Hello, world!")
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexTurnStartParams::to_json" {
  let params : CodexTurnStartParams = {
    thread_id: "thread-123",
    input: [CodexInputItem::text("Test prompt")],
    cwd: "/workspace",
    approval_policy: "never",
    sandbox_policy: None,
  }
  let json = params.to_json()
  match json {
    { "threadId": String(tid), "input": Array(inputs), .. } => {
      assert_eq(tid, "thread-123")
      assert_eq(inputs.length(), 1)
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexEventType::from_string" {
  assert_eq(
    CodexEventType::from_string("session_configured"),
    SessionConfigured,
  )
  assert_eq(CodexEventType::from_string("task_started"), TaskStarted)
  assert_eq(CodexEventType::from_string("task_complete"), TaskComplete)
  assert_eq(CodexEventType::from_string("agent_message"), AgentMessage)
  assert_eq(
    CodexEventType::from_string("agent_message_delta"),
    AgentMessageDelta,
  )
  assert_eq(
    CodexEventType::from_string("agent_message_content_delta"),
    AgentMessageContentDelta,
  )
  assert_eq(CodexEventType::from_string("item_started"), ItemStarted)
  assert_eq(CodexEventType::from_string("item_completed"), ItemCompleted)
  assert_eq(CodexEventType::from_string("user_message"), UserMessage)
  assert_eq(
    CodexEventType::from_string("unknown_event"),
    Unknown("unknown_event"),
  )
}

///|
test "CodexTurnStatus::from_string" {
  assert_eq(CodexTurnStatus::from_string("inProgress"), InProgress)
  assert_eq(CodexTurnStatus::from_string("completed"), Completed)
  assert_eq(CodexTurnStatus::from_string("interrupted"), Interrupted)
  assert_eq(CodexTurnStatus::from_string("failed"), Failed)
  assert_eq(CodexTurnStatus::from_string("unknown"), Failed)
}

///|
test "CodexDynamicTool::to_json uses inputSchema" {
  let tool : CodexDynamicTool = {
    name: "test_tool",
    description: "A test tool",
    schema: { "type": "object", "properties": {} },
  }
  let json = tool.to_json()
  match json {
    {
      "name": String(name),
      "description": String(desc),
      "inputSchema": schema,
      ..
    } => {
      assert_eq(name, "test_tool")
      assert_eq(desc, "A test tool")
      match schema {
        { "type": String(t), .. } => assert_eq(t, "object")
        _ => fail("Expected schema to be object")
      }
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexSandboxPolicy::to_json correct shape" {
  let policy = CodexSandboxPolicy::workspace_write(["/workspace", "/tmp"])
  let json = policy.to_json()
  match json {
    {
      "type": String(t),
      "writableRoots": Array(roots),
      "readOnlyAccess": { "type": String(roa), .. },
      "networkAccess": False,
      ..
    } => {
      assert_eq(t, "workspaceWrite")
      assert_eq(roots.length(), 2)
      assert_eq(roa, "fullAccess")
    }
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexApprovalDecision::to_json" {
  let decision = CodexApprovalDecision::AcceptForSession
  let json = decision.to_json()
  match json {
    { "decision": String(d), .. } => assert_eq(d, "acceptForSession")
    _ => fail("Unexpected JSON structure")
  }
}

///|
test "CodexConfig::default" {
  let config = CodexConfig::default()
  assert_eq(config.command, "codex app-server")
  assert_eq(config.turn_timeout_ms, 3600000)
  assert_eq(config.read_timeout_ms, 5000)
  assert_eq(config.stall_timeout_ms, 300000)
}

///|
test "build_thread_start_request" {
  let req = build_thread_start_request(2, "/workspace", "never", [])
  assert_eq(req.id, Some(2))
  assert_eq(req.rpc_method, "thread/start")
}

///|
test "build_turn_start_request" {
  let req = build_turn_start_request(
    3, "thread-abc", "What is 2+2?", "/workspace", "never",
  )
  assert_eq(req.id, Some(3))
  assert_eq(req.rpc_method, "turn/start")
}

///|
test "build_initialized_notification" {
  let req = build_initialized_notification()
  assert_eq(req.id, None)
  assert_eq(req.rpc_method, "initialized")
}

///|
test "CodexTokenUsage::from_json nested total" {
  let json : Json = {
    "total": {
      "inputTokens": 100,
      "outputTokens": 50,
      "totalTokens": 150,
      "cachedInputTokens": 30,
      "reasoningOutputTokens": 10,
    },
  }
  let usage = CodexTokenUsage::from_json(json)
  match usage {
    Some(u) => {
      assert_eq(u.input_tokens, 100)
      assert_eq(u.output_tokens, 50)
      assert_eq(u.total_tokens, 150)
      assert_eq(u.cached_input_tokens, 30)
      assert_eq(u.reasoning_output_tokens, 10)
    }
    None => fail("Failed to parse token usage")
  }
}

// =============================================================================
// Fixture-based Tests
// =============================================================================

///|
fn read_codex_fixture(filename : String) -> String raise {
  @utils.read_testdata("testdata/codex/" + filename)
}

///|
fn read_codex_fixture_json(filename : String) -> Json raise {
  @json.parse(read_codex_fixture(filename))
}

///|
fn read_codex_fixture_lines(filename : String) -> Array[String] raise {
  @utils.split_lines(read_codex_fixture(filename))
}

///|
test "fixture: parse initialize response" {
  let json = read_codex_fixture_json("initialize_response.json") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_eq(r.error, None)
      match r.result {
        Some({ "userAgent": String(ua), .. }) =>
          assert_true(ua.contains("fixture-capture"))
        _ => fail("Expected userAgent in result")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "fixture: parse thread/start response" {
  let json = read_codex_fixture_json("thread_start_response.json") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(2))
      match r.result {
        Some(result) => {
          let thread_resp = CodexThreadStartResponse::from_json(result)
          match thread_resp {
            Some(tr) =>
              match tr.thread {
                Some(t) =>
                  // Real thread IDs are UUIDs
                  assert_true(t.id.length() > 0)
                None => fail("Expected thread in response")
              }
            None => fail("Failed to parse thread start response")
          }
          // Check additional fields in real response
          match result {
            {
              "model": String(model),
              "modelProvider": String(provider),
              "approvalPolicy": String(policy),
              ..
            } => {
              assert_true(model.length() > 0)
              assert_true(provider.length() > 0)
              assert_eq(policy, "never")
            }
            _ => fail("Expected model and approvalPolicy in response")
          }
        }
        None => fail("Expected result")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "fixture: parse turn/start response" {
  let json = read_codex_fixture_json("turn_start_response.json") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(3))
      match r.result {
        Some(result) => {
          let turn_resp = CodexTurnStartResponse::from_json(result)
          match turn_resp {
            Some(tr) =>
              match tr.turn {
                Some(t) => assert_true(t.id.length() > 0)
                None => fail("Expected turn in response")
              }
            None => fail("Failed to parse turn start response")
          }
          // Check turn status
          match result {
            { "turn": { "status": String(status), .. }, .. } =>
              assert_eq(status, "inProgress")
            _ => fail("Expected turn.status")
          }
        }
        None => fail("Expected result")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "fixture: parse error response" {
  let json = read_codex_fixture_json("error_response.json") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  let resp = CodexRpcResponse::from_json(json)
  match resp {
    Some(r) => {
      assert_eq(r.id, Some(4))
      assert_eq(r.result, None)
      match r.error {
        Some(e) => {
          assert_eq(e.code, -32600)
          assert_true(e.message.contains("Invalid request"))
        }
        None => fail("Expected error")
      }
    }
    None => fail("Failed to parse response")
  }
}

///|
test "fixture: parse events.jsonl task_started" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find task_started event
  let mut found = false
  for line in lines {
    if line.contains("task_started") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("codex/event/task_started"),
          "params": {
            "msg": {
              "type": String("task_started"),
              "turn_id": String(tid),
              ..
            },
            ..
          },
          ..
        } => {
          assert_true(tid.length() > 0)
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl agent_message_delta" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find agent_message_delta event
  let mut found = false
  for line in lines {
    if line.contains("item/agentMessage/delta") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("item/agentMessage/delta"),
          "params": { "delta": String(delta), .. },
          ..
        } => {
          assert_true(delta.length() > 0)
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl agent_message" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find agent_message event (final answer, not delta)
  let mut found = false
  for line in lines {
    if line.contains("codex/event/agent_message") &&
      not(line.contains("agent_message_delta")) &&
      not(line.contains("agent_message_content_delta")) {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("codex/event/agent_message"),
          "params": {
            "msg": { "type": String(t), "message": String(msg), .. },
            ..
          },
          ..
        } => {
          assert_eq(t, "agent_message")
          assert_eq(CodexEventType::from_string(t), AgentMessage)
          assert_true(msg.length() > 0)
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl turn inProgress status" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find turn/started event with inProgress status
  let mut found = false
  for line in lines {
    if line.contains("\"method\":\"turn/started\"") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("turn/started"),
          "params": { "turn": { "status": String(status), .. }, .. },
          ..
        } => {
          assert_eq(status, "inProgress")
          assert_eq(CodexTurnStatus::from_string(status), InProgress)
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl token_usage" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find token_count event
  let mut found = false
  for line in lines {
    if line.contains("thread/tokenUsage/updated") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("thread/tokenUsage/updated"),
          "params": { "tokenUsage": usage, .. },
          ..
        } => {
          let parsed = CodexTokenUsage::from_json(usage)
          match parsed {
            Some(u) => {
              assert_true(u.input_tokens > 0)
              assert_true(u.output_tokens > 0)
              assert_true(u.total_tokens > 0)
              found = true
            }
            None => fail("Failed to parse token usage from fixture")
          }
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl task_complete" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find task_complete event
  let mut found = false
  for line in lines {
    if line.contains("task_complete") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("codex/event/task_complete"),
          "params": {
            "msg": {
              "type": String("task_complete"),
              "turn_id": String(tid),
              "last_agent_message": String(msg),
              ..
            },
            ..
          },
          ..
        } => {
          assert_true(tid.length() > 0)
          assert_true(msg.length() > 0)
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "fixture: parse events.jsonl turn_completed" {
  let lines = read_codex_fixture_lines("events.jsonl") catch {
    err => {
      fail("Failed to load fixture: " + err.to_string())
      return
    }
  }
  // Find turn/completed event
  let mut found = false
  for line in lines {
    if line.contains("\"method\":\"turn/completed\"") {
      let json = @json.parse(line) catch { _ => continue }
      match json {
        {
          "method": String("turn/completed"),
          "params": { "turn": { "status": String(status), .. }, .. },
          ..
        } => {
          assert_eq(status, "completed")
          found = true
          break
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}
