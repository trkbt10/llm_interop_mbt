///|
/// Whitebox coverage for Codex protocol builders and parser fallbacks

///|
test "rpc helpers and thread-start parsers cover defaults, sandbox image, dynamic tools, and optional thread fields" {
  let success = rpc_response(Some(7), { "ok": true })
  assert_true(success.contains("\"id\":7"))
  assert_true(success.contains("\"result\""))

  let failure = rpc_error(Some(8), -32603, "boom")
  assert_true(failure.contains("\"id\":8"))
  assert_true(failure.contains("\"message\":\"boom\""))

  let notification = rpc_notification("thread/updated", { "threadId": "th_1" })
  assert_true(notification.contains("\"method\":\"thread/updated\""))
  assert_true(notification.contains("\"params\""))

  let ipc = ipc_error_event("offline")
  assert_true(ipc.contains("\"method\":\"error\""))
  assert_true(ipc.contains("\"message\":\"offline\""))

  match
    CodexThreadStartParams::from_json({
      "model": "gpt-5-codex",
      "sandbox": { "kind": "docker", "image": "ubuntu:24.04" },
      "experimentalRawEvents": true,
      "persistExtendedHistory": true,
      "dynamicTools": Json::array([
        {
          "name": "lookup",
          "description": "Search docs",
          "inputSchema": { "type": "object" },
        },
        { "bad": true },
      ]),
    }) {
    Some(params) => {
      assert_eq(params.model, "gpt-5-codex")
      assert_eq(params.cwd, ".")
      assert_eq(params.approval_policy, "never")
      assert_eq(params.service_name, "")
      assert_eq(params.personality, "pragmatic")
      assert_true(params.experimental_raw_events)
      assert_true(params.persist_extended_history)
      assert_eq(params.dynamic_tools.length(), 1)
      match params.sandbox {
        Some(sandbox) => {
          assert_eq(sandbox.kind, "docker")
          assert_eq(sandbox.image, Some("ubuntu:24.04"))
        }
        None => fail("Expected sandbox config")
      }
    }
    None => fail("Expected thread start params")
  }

  let thread_start_json = {
    ..CodexThreadStartParams::from_json({
      "model": "gpt-5-codex",
      "cwd": "/tmp",
      "approvalPolicy": "on-request",
      "sandbox": { "kind": "docker", "image": "ubuntu:24.04" },
      "serviceName": "interop",
      "personality": "strict",
      "dynamicTools": Json::array([
        {
          "name": "lookup",
          "description": "Search docs",
          "inputSchema": { "type": "object" },
        },
      ]),
    }).unwrap()
  }.to_json()
  match thread_start_json {
    {
      "sandbox": { "kind": "docker", "image": "ubuntu:24.04", .. },
      "dynamicTools": Array(dynamic_tools),
      ..
    } => assert_eq(dynamic_tools.length(), 1)
    _ => fail("Expected serialized thread start params")
  }

  assert_eq(CodexThreadStartResponse::from_json({}), Some({ thread: None }))
  assert_eq(CodexThread::from_json({}), None)
  match CodexThreadStartParams::from_json({ "model": "gpt-5-codex" }) {
    Some(params) => assert_eq(params.sandbox, None)
    None => fail("Expected default thread start params")
  }
  assert_eq(
    CodexSandboxConfig::{ kind: "docker", image: Some("ubuntu:24.04") }.to_json(),
    { "kind": "docker", "image": "ubuntu:24.04" },
  )
}

///|
test "turn-start and sandbox helpers cover invalid inputs, defaults, optional fields, and constructors" {
  assert_eq(CodexTurnStartParams::from_json({ "threadId": "th_1" }), None)
  match
    CodexTurnStartParams::from_json({
      "threadId": "th_personality",
      "input": Json::array([{ "type": "text", "text": "Hello" }]),
      "personality": "strict",
      "sandboxPolicy": { "type": "none" },
    }) {
    Some(params) => {
      assert_eq(params.personality, Some("strict"))
      match params.sandbox_policy {
        Some(policy) => {
          assert_eq(policy.writable_roots.length(), 0)
          assert_eq(policy.read_only_access, None)
          assert_false(policy.network_access)
        }
        None => fail("Expected sandbox policy")
      }
    }
    None => fail("Expected turn start params with personality")
  }

  match
    CodexTurnStartParams::from_json({
      "threadId": "th_1",
      "input": Json::array([
        { "type": "text", "text": "Hello", "text_elements": Json::array([1]) },
        { "bad": true },
      ]),
      "sandboxPolicy": {
        "type": "workspaceWrite",
        "writableRoots": Json::array([Json::string("/tmp"), Json::number(1.0)]),
        "readOnlyAccess": { "type": "workspaceOnly" },
        "networkAccess": true,
      },
    }) {
    Some(params) => {
      assert_eq(params.thread_id, "th_1")
      assert_eq(params.input.length(), 1)
      assert_eq(params.model, "codex")
      assert_eq(params.effort, None)
      assert_eq(params.personality, None)
      assert_eq(params.cwd, ".")
      assert_eq(params.approval_policy, "never")
      match params.sandbox_policy {
        Some(policy) => {
          assert_eq(policy.sandbox_type, "workspaceWrite")
          assert_eq(policy.writable_roots, ["/tmp"])
          assert_true(policy.network_access)
          match policy.read_only_access {
            Some(roa) => assert_eq(roa.access_type, "workspaceOnly")
            None => fail("Expected read-only access")
          }
        }
        None => fail("Expected sandbox policy")
      }
    }
    None => fail("Expected turn start params")
  }

  let turn_json = CodexTurnStartParams::{
    thread_id: "th_2",
    input: [CodexInputItem::text("Prompt")],
    model: "gpt-5-codex",
    effort: Some("high"),
    personality: Some("strict"),
    cwd: "/work",
    approval_policy: "on-request",
    sandbox_policy: Some(CodexSandboxPolicy::workspace_write(["/work"])),
  }.to_json()
  match turn_json {
    {
      "effort": "high",
      "personality": "strict",
      "sandboxPolicy": {
        "type": "workspaceWrite",
        "writableRoots": Array(writable_roots),
        ..
      },
      ..
    } => assert_eq(writable_roots.length(), 1)
    _ => fail("Expected serialized turn start params")
  }

  assert_eq(CodexTurnStartResponse::from_json({}), Some({ turn: None }))
  assert_eq(CodexTurn::from_json({}), None)
  assert_eq(
    CodexInputItem::from_json({
      "type": "text",
      "text": "Hello",
      "text_elements": Json::array([Json::number(1.0)]),
    }),
    Some({ kind: "text", text: "Hello", text_elements: [Json::number(1.0)] }),
  )
  assert_eq(CodexInputItem::from_json({ "type": "text" }), None)

  assert_eq(
    CodexSandboxPolicy::{
      sandbox_type: "workspaceWrite",
      writable_roots: ["/work"],
      read_only_access: None,
      network_access: false,
    }.to_json(),
    {
      "type": "workspaceWrite",
      "writableRoots": Json::array([Json::string("/work")]),
      "networkAccess": false,
    },
  )
  assert_eq(CodexSandboxPolicy::none(), {
    sandbox_type: "none",
    writable_roots: [],
    read_only_access: None,
    network_access: false,
  })
  assert_eq(CodexSandboxPolicy::full_access(), {
    sandbox_type: "fullAccess",
    writable_roots: [],
    read_only_access: Some({ access_type: "fullAccess" }),
    network_access: true,
  })
  assert_eq(
    CodexDynamicTool::from_tool_definition(
      @types.ToolDefinition::new(name="lookup", description="Search docs", parameters={
        "type": "object",
      }),
    ),
    { name: "lookup", description: "Search docs", schema: { "type": "object" } },
  )
}

///|
test "event, token, approval, and model helpers cover alternate formats and fallbacks" {
  assert_eq(CodexEventType::from_string("token_count"), TokenCount)
  assert_eq(
    CodexEventType::from_string("agent_message_completed"),
    AgentMessageCompleted,
  )
  assert_eq(
    CodexEventType::from_string("token_usage_updated"),
    TokenUsageUpdated,
  )
  assert_eq(
    CodexEventType::from_string("rate_limits_updated"),
    RateLimitsUpdated,
  )
  assert_eq(
    CodexEventType::from_string("turn_input_required"),
    TurnInputRequired,
  )

  assert_eq(
    CodexTokenUsage::from_json({
      "info": {
        "total_token_usage": {
          "input_tokens": 10,
          "output_tokens": 5,
          "total_tokens": 15,
        },
      },
    }),
    Some({
      input_tokens: 10,
      output_tokens: 5,
      total_tokens: 15,
      cached_input_tokens: 0,
      reasoning_output_tokens: 0,
    }),
  )
  assert_eq(
    CodexTokenUsage::from_json({
      "inputTokens": 3,
      "outputTokens": 4,
      "totalTokens": 7,
      "reasoningOutputTokens": 2,
    }),
    Some({
      input_tokens: 3,
      output_tokens: 4,
      total_tokens: 7,
      cached_input_tokens: 0,
      reasoning_output_tokens: 2,
    }),
  )
  assert_eq(
    CodexTokenUsage::from_json({
      "inputTokens": 3,
      "outputTokens": 4,
      "totalTokens": 7,
    }),
    Some({
      input_tokens: 3,
      output_tokens: 4,
      total_tokens: 7,
      cached_input_tokens: 0,
      reasoning_output_tokens: 0,
    }),
  )
  assert_eq(CodexTokenUsage::from_json({ "bad": true }), None)

  assert_eq(CodexApprovalDecision::AcceptOnce.to_string(), "acceptOnce")
  assert_eq(CodexApprovalDecision::Reject.to_string(), "reject")
  assert_eq(build_approval_response(5, CodexApprovalDecision::AcceptOnce), {
    "id": 5,
    "result": { "decision": "acceptOnce" },
  })

  match
    CodexModelInfo::from_json({
      "id": "model_1",
      "model": "gpt-5-codex",
      "hidden": true,
      "supportedReasoningEfforts": Json::array([
        { "reasoning_effort": "high", "description": "High effort" },
        { "bad": true },
      ]),
      "inputModalities": Json::array([Json::string("text"), Json::number(1.0)]),
      "isDefault": true,
    }) {
    Some(info) => {
      assert_eq(info.display_name, "gpt-5-codex")
      assert_true(info.hidden)
      assert_eq(info.supported_reasoning_efforts.length(), 1)
      assert_eq(info.input_modalities, ["text"])
      assert_true(info.is_default)
    }
    None => fail("Expected model info")
  }
  assert_eq(CodexModelInfo::from_json({}), None)
}

///|
test "fork, steer, and model-list parsers cover invalid elements and missing data" {
  assert_eq(CodexThreadForkParams::from_json({}), None)

  match
    CodexTurnSteerParams::from_json({
      "threadId": "th_1",
      "expectedTurnId": "turn_1",
      "input": Json::array([
        { "type": "text", "text": "Continue" },
        { "bad": true },
      ]),
    }) {
    Some(params) => {
      assert_eq(params.thread_id, "th_1")
      assert_eq(params.expected_turn_id, "turn_1")
      assert_eq(params.input.length(), 1)
    }
    None => fail("Expected steer params")
  }
  assert_eq(
    CodexTurnSteerParams::from_json({
      "threadId": "th_1",
      "expectedTurnId": "turn_1",
    }),
    None,
  )

  let models = parse_model_list_response({
    "data": Json::array([
      { "id": "m1", "model": "gpt-5-codex" },
      { "bad": true },
    ]),
  })
  assert_eq(models.length(), 1)
  assert_eq(models[0].id, "m1")
  assert_eq(parse_model_list_response({ "bad": true }).length(), 0)
}
