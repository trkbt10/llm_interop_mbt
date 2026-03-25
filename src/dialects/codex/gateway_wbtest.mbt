///|
/// Whitebox coverage for Codex gateway helpers and model-list behavior

///|
test "gateway helpers cover auth, upstream preparation, and model list" {
  assert_eq(default_base_url(), "")
  assert_eq(auth_headers("sk").length(), 0)

  let init_session : CodexSession = {
    phase: Initializing,
    thread_id: "",
    next_id: 7,
    cwd: "/workspace",
    approval_policy: "never",
    model: "codex-fallback",
  }
  let init_req = prepare_codex_upstream(
    "{\"prompt\":\"plain prompt body\"}", init_session,
  )
  assert_eq(init_req.steps.length(), 4)
  assert_eq(init_req.steps[0].kind, Request)
  assert_eq(init_req.steps[3].kind, TurnStart)
  assert_true(init_req.steps[3].message.contains("plain prompt body"))
  assert_true(init_req.steps[2].message.contains("codex-fallback"))
  assert_eq(init_req.next_session.model, "codex-fallback")

  let ready_session : CodexSession = {
    phase: Ready,
    thread_id: "thread-1",
    next_id: 10,
    cwd: "/workspace",
    approval_policy: "never",
    model: "codex",
  }
  let ready_models = prepare_codex_model_list(ready_session)
  assert_eq(ready_models.steps.length(), 1)
  assert_eq(ready_models.steps[0].kind, Request)
  assert_eq(ready_models.next_session.next_id, 11)

  let init_models = prepare_codex_model_list(init_session)
  assert_eq(init_models.steps.length(), 3)
  assert_eq(init_models.steps[0].kind, Request)
  assert_eq(init_models.steps[1].kind, Notification)
  assert_eq(init_models.steps[2].kind, Request)
  assert_eq(init_models.next_session.phase, Initializing)

  let models = parse_codex_model_list_result(
    {
      "data": [
        { "id": "m1", "model": "o3-mini" },
        { "id": "m2", "model": "codex-mini-latest" },
      ],
    },
    "codex-provider",
  )
  assert_eq(models.length(), 2)
  match models[0] {
    { "id": "o3-mini", "object": "model", "owned_by": "codex-provider", .. } =>
      ()
    _ => fail("Expected normalized model listing")
  }
}

///|
test "panic gateway helpers reject non-protocol prompt bodies" {
  let session : CodexSession = {
    phase: Initializing,
    thread_id: "",
    next_id: 7,
    cwd: "/workspace",
    approval_policy: "never",
    model: "codex-fallback",
  }
  ignore(prepare_codex_upstream("plain prompt body", session))
}

///|
test "gateway session update and patch helpers cover fallback branches" {
  let session = CodexSession::new("/tmp")

  let init_updated = update_session_from_init_response(session, { "ok": true })
  assert_eq(init_updated.phase, Initializing)

  assert_eq(
    patch_turn_start_thread_id(
      "{\"id\":3,\"method\":\"turn/start\",\"params\":{}}", "thread-xyz",
    ),
    "{\"id\":3,\"method\":\"turn/start\",\"params\":{\"threadId\":\"thread-xyz\"}}",
  )

  let no_params = "{\"id\":3,\"method\":\"turn/start\"}"
  assert_eq(patch_turn_start_thread_id(no_params, "thread-xyz"), no_params)

  let scalar = "\"turn/start\""
  assert_eq(patch_turn_start_thread_id(scalar, "thread-xyz"), scalar)
}
