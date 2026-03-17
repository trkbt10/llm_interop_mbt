///|
/// `claude mcp serve` session management
///
/// Follows the CodexSession pattern:
/// - Session tracks lifecycle phase and cached tools
/// - Upstream requests are sequences of MCP JSON-RPC steps for the host to execute
///
/// Uses src/mcp/ for all protocol-level JSON-RPC building.

// =============================================================================
// DialectSpec helpers (called by src/gateway/dialect.mbt)
// =============================================================================

///|
/// `claude mcp serve` has no HTTP endpoint; transport is stdio
pub fn claude_mcp_default_base_url() -> String {
  ""
}

///|
/// No auth headers — `claude mcp serve` uses stdio, not HTTP
pub fn claude_mcp_auth_headers(_api_key : String) -> Map[String, String] {
  {}
}

// =============================================================================
// Session state
// =============================================================================

///|
/// Session state for a `claude mcp serve` subprocess
pub(all) struct ClaudeMcpSession {
  phase : ClaudeMcpPhase
  next_id : Int
  tools : Array[@mcp.McpToolDefinition] // cached tools/list result
} derive(Show)

///|
pub(all) enum ClaudeMcpPhase {
  /// No messages sent yet
  Uninitialized
  /// initialize + initialized done, ready for tools/list or tools/call
  Ready
} derive(Show, Eq)

///|
pub fn ClaudeMcpSession::new() -> ClaudeMcpSession {
  { phase: Uninitialized, next_id: 1, tools: [] }
}

// =============================================================================
// Upstream request types — uses @jsonrpc.RpcStep directly
// =============================================================================

///|
/// Full upstream request — sequence of JSON-RPC steps
pub(all) struct ClaudeMcpUpstreamRequest {
  steps : Array[@jsonrpc.RpcStep]
  next_session : ClaudeMcpSession
} derive(Show)

// =============================================================================
// Upstream preparation
// =============================================================================

///|
/// Prepare initialize sequence: initialize → initialized (notification)
pub fn prepare_initialize(
  session : ClaudeMcpSession,
) -> ClaudeMcpUpstreamRequest {
  let id = session.next_id
  let init_msg = @mcp.build_initialize_request(id, "llm_interop", "0.1.0")
  let notif_msg = @mcp.build_initialized_notification()
  {
    steps: [
      { message: init_msg, kind: @jsonrpc.Request },
      { message: notif_msg, kind: @jsonrpc.Notification },
    ],
    next_session: { ..session, phase: Ready, next_id: id + 1 },
  }
}

///|
/// Prepare tools/list request, including init if needed
pub fn prepare_tools_list(
  session : ClaudeMcpSession,
) -> ClaudeMcpUpstreamRequest {
  let id = session.next_id
  match session.phase {
    Ready => {
      let msg = @mcp.build_tools_list_request(id)
      {
        steps: [{ message: msg, kind: @jsonrpc.Request }],
        next_session: { ..session, next_id: id + 1 },
      }
    }
    Uninitialized => {
      let init_msg = @mcp.build_initialize_request(id, "llm_interop", "0.1.0")
      let notif_msg = @mcp.build_initialized_notification()
      let list_msg = @mcp.build_tools_list_request(id + 1)
      {
        steps: [
          { message: init_msg, kind: @jsonrpc.Request },
          { message: notif_msg, kind: @jsonrpc.Notification },
          { message: list_msg, kind: @jsonrpc.Request },
        ],
        next_session: { ..session, phase: Ready, next_id: id + 2 },
      }
    }
  }
}

///|
/// Prepare tools/call request, including init if needed
pub fn prepare_tools_call(
  session : ClaudeMcpSession,
  tool_name : String,
  arguments : Json,
) -> ClaudeMcpUpstreamRequest {
  let id = session.next_id
  match session.phase {
    Ready => {
      let msg = @mcp.build_tools_call_request(id, tool_name, arguments)
      {
        steps: [{ message: msg, kind: @jsonrpc.Request }],
        next_session: { ..session, next_id: id + 1 },
      }
    }
    Uninitialized => {
      let init_msg = @mcp.build_initialize_request(id, "llm_interop", "0.1.0")
      let notif_msg = @mcp.build_initialized_notification()
      let call_msg = @mcp.build_tools_call_request(
        id + 1, tool_name, arguments,
      )
      {
        steps: [
          { message: init_msg, kind: @jsonrpc.Request },
          { message: notif_msg, kind: @jsonrpc.Notification },
          { message: call_msg, kind: @jsonrpc.Request },
        ],
        next_session: { ..session, phase: Ready, next_id: id + 2 },
      }
    }
  }
}

///|
/// Update session with tools from tools/list response
pub fn update_session_tools(
  session : ClaudeMcpSession,
  tools : Array[@mcp.McpToolDefinition],
) -> ClaudeMcpSession {
  { ..session, tools, }
}
