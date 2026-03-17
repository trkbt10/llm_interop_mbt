///|
/// Codex app-server gateway behavior
///
/// Unlike HTTP REST dialects, Codex uses JSON-RPC over JSONL.
/// This module provides:
/// - DialectSpec helpers (URL, headers)
/// - Session state management (initialize → thread → turns)
/// - Upstream request preparation (JSON-RPC message sequence building)

// =============================================================================
// DialectSpec helpers (called by src/gateway/dialect.mbt)
// =============================================================================

///|
/// Codex app-server has no HTTP endpoint; this is a placeholder
/// for DialectSpec compatibility. The actual transport is stdio.
pub fn codex_default_base_url() -> String {
  ""
}

///|
/// No auth headers needed — Codex uses stdio, not HTTP.
pub fn codex_auth_headers(_api_key : String) -> Map[String, String] {
  {}
}

// =============================================================================
// Session state
// =============================================================================

///|
/// Codex session state — tracks the JSON-RPC lifecycle.
/// Managed by the host runtime, threaded through gateway functions.
pub(all) struct CodexSession {
  /// Whether initialize + initialized + thread/start have completed
  phase : CodexSessionPhase
  /// Thread ID returned by thread/start response
  thread_id : String
  /// Next JSON-RPC request ID
  next_id : Int
  /// Working directory for thread/turn
  cwd : String
  /// Approval policy for thread/turn
  approval_policy : String
} derive(Show, Eq)

///|
/// Session lifecycle phase
pub(all) enum CodexSessionPhase {
  /// No messages sent yet
  Uninitialized
  /// initialize sent, awaiting response
  Initializing
  /// initialized notification sent, thread/start sent, awaiting response
  ThreadStarting
  /// Thread is active, ready for turn/start
  Ready
  /// turn/start sent, awaiting events + turn/completed
  TurnInProgress
} derive(Show, Eq)

///|
pub fn CodexSession::new(cwd : String) -> CodexSession {
  {
    phase: Uninitialized,
    thread_id: "",
    next_id: 1,
    cwd,
    approval_policy: "never",
  }
}

// =============================================================================
// Upstream request types
// =============================================================================

///|
/// A single step in the Codex JSON-RPC session setup sequence.
/// The host runtime executes steps in order, checking responses between them.
pub(all) struct CodexRpcStep {
  /// Serialized JSON-RPC message
  message : String
  /// What kind of step this is (determines how host handles the response)
  kind : CodexStepKind
} derive(Show)

///|
pub(all) enum CodexStepKind {
  /// Send and expect a JSON-RPC response with result
  Request
  /// Send without expecting a response (notification)
  Notification
  /// Send and stream JSONL events until turn/completed
  TurnStart
} derive(Show, Eq)

///|
/// Full Codex upstream request — sequence of RPC steps to execute.
pub(all) struct CodexUpstreamRequest {
  /// Steps to execute in order
  steps : Array[CodexRpcStep]
  /// Session state after all steps complete successfully
  next_session : CodexSession
} derive(Show)

// =============================================================================
// Upstream preparation
// =============================================================================

///|
/// Build the JSON-RPC message sequence for a Codex turn.
/// Depending on session phase, may include initialization steps.
pub fn prepare_codex_upstream(
  body : String,
  session : CodexSession,
) -> CodexUpstreamRequest {
  let json = @json.parse(body) catch { _ => Json::null() }
  let prompt = match json {
    { "prompt": String(p), .. } => p
    _ => body
  }
  match session.phase {
    Uninitialized => build_full_sequence(session, prompt)
    Ready => build_turn_only(session, prompt)
    // For other phases, attempt recovery by doing full init
    _ => build_full_sequence(session, prompt)
  }
}

///|
/// Full initialization sequence: initialize → initialized → thread/start → turn/start
fn build_full_sequence(
  session : CodexSession,
  prompt : String,
) -> CodexUpstreamRequest {
  let id = session.next_id
  let init_req = build_initialize_request(id, "llm_interop", "0.1.0")
  let init_notif = build_initialized_notification()
  let thread_req = build_thread_start_request(
    id + 1, session.cwd, session.approval_policy, [],
  )
  // turn/start needs thread_id from thread/start response.
  // We build it with empty thread_id; host fills it from the response.
  let turn_req = build_turn_start_request(
    id + 2, "", prompt, session.cwd, session.approval_policy,
  )
  {
    steps: [
      { message: init_req.to_json().stringify(), kind: Request },
      { message: init_notif.to_json().stringify(), kind: Notification },
      { message: thread_req.to_json().stringify(), kind: Request },
      { message: turn_req.to_json().stringify(), kind: TurnStart },
    ],
    next_session: {
      ..session,
      phase: TurnInProgress,
      next_id: id + 3,
    },
  }
}

///|
/// Single turn on an existing session
fn build_turn_only(
  session : CodexSession,
  prompt : String,
) -> CodexUpstreamRequest {
  let turn_req = build_turn_start_request(
    session.next_id,
    session.thread_id,
    prompt,
    session.cwd,
    session.approval_policy,
  )
  {
    steps: [{ message: turn_req.to_json().stringify(), kind: TurnStart }],
    next_session: {
      ..session,
      phase: TurnInProgress,
      next_id: session.next_id + 1,
    },
  }
}

///|
/// Update session from a thread/start response (extract thread_id).
pub fn update_session_from_thread_response(
  session : CodexSession,
  response_json : Json,
) -> CodexSession {
  match response_json {
    { "result": { "thread": { "id": String(tid), .. }, .. }, .. } =>
      { ..session, thread_id: tid, phase: Ready }
    _ => session
  }
}

///|
/// Update session from an initialize response.
pub fn update_session_from_init_response(
  session : CodexSession,
  _response_json : Json,
) -> CodexSession {
  { ..session, phase: Initializing }
}

///|
/// Mark session as ready after turn completes.
pub fn mark_session_turn_complete(session : CodexSession) -> CodexSession {
  { ..session, phase: Ready }
}

///|
/// Patch a turn/start message with the actual thread_id.
/// Called by host after receiving thread/start response.
pub fn patch_turn_start_thread_id(
  message : String,
  thread_id : String,
) -> String {
  let json = @json.parse(message) catch { _ => return message }
  match json {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) => {
          params["threadId"] = Json::string(thread_id)
          obj["params"] = Json::object(params)
          Json::object(obj).stringify()
        }
        _ => message
      }
    _ => message
  }
}
