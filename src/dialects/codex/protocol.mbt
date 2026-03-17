///|
/// Codex app-server JSON-RPC protocol definitions
/// Based on symphony implementation

// =============================================================================
// JSON-RPC Base Types
// =============================================================================

///|
/// JSON-RPC request message
pub(all) struct CodexRpcRequest {
  id : Int?
  rpc_method : String
  params : Json?
} derive(Show, Eq)

///|
pub fn CodexRpcRequest::to_json(self : CodexRpcRequest) -> Json {
  let obj : Map[String, Json] = {}
  match self.id {
    Some(id) => obj["id"] = Json::number(id.to_double())
    None => ()
  }
  obj["method"] = Json::string(self.rpc_method)
  match self.params {
    Some(params) => obj["params"] = params
    None => ()
  }
  Json::object(obj)
}

///|
/// JSON-RPC response message
pub(all) struct CodexRpcResponse {
  id : Int?
  result : Json?
  error : CodexRpcError?
} derive(Show, Eq)

///|
/// JSON-RPC error
pub(all) struct CodexRpcError {
  code : Int
  message : String
} derive(Show, Eq, ToJson, FromJson)

///|
pub fn CodexRpcResponse::from_json(json : Json) -> CodexRpcResponse? {
  match json {
    { "id": Number(id, ..), "result": result, .. } =>
      Some({ id: Some(id.to_int()), result: Some(result), error: None })
    {
      "id": Number(id, ..),
      "error": { "code": Number(code, ..), "message": String(msg), .. },
      ..
    } =>
      Some({
        id: Some(id.to_int()),
        result: None,
        error: Some({ code: code.to_int(), message: msg }),
      })
    { "result": result, .. } =>
      Some({ id: None, result: Some(result), error: None })
    _ => None
  }
}

// =============================================================================
// Initialize Request/Response
// =============================================================================

///|
/// Initialize request parameters
pub(all) struct CodexInitializeParams {
  client_info : CodexClientInfo
  capabilities : CodexCapabilities
} derive(Show, Eq)

///|
pub fn CodexInitializeParams::to_json(self : CodexInitializeParams) -> Json {
  {
    "clientInfo": self.client_info.to_json(),
    "capabilities": self.capabilities.to_json(),
  }
}

///|
/// Client information
pub(all) struct CodexClientInfo {
  name : String
  version : String
} derive(Show, Eq)

///|
pub fn CodexClientInfo::to_json(self : CodexClientInfo) -> Json {
  { "name": self.name, "version": self.version }
}

///|
/// Client capabilities
pub(all) struct CodexCapabilities {
  experimental_api : Bool
} derive(Show, Eq)

///|
pub fn CodexCapabilities::to_json(self : CodexCapabilities) -> Json {
  { "experimentalApi": self.experimental_api }
}

// =============================================================================
// Thread Management
// =============================================================================

///|
/// Thread start request parameters
pub(all) struct CodexThreadStartParams {
  model : String
  cwd : String
  approval_policy : String
  sandbox : CodexSandboxConfig?
  service_name : String
  personality : String
  experimental_raw_events : Bool
  persist_extended_history : Bool
  dynamic_tools : Array[CodexDynamicTool]
} derive(Show, Eq)

///|
pub fn CodexThreadStartParams::to_json(self : CodexThreadStartParams) -> Json {
  let obj : Map[String, Json] = {}
  obj["model"] = Json::string(self.model)
  obj["cwd"] = Json::string(self.cwd)
  obj["approvalPolicy"] = Json::string(self.approval_policy)
  match self.sandbox {
    Some(sandbox) => obj["sandbox"] = sandbox.to_json()
    None => ()
  }
  obj["serviceName"] = Json::string(self.service_name)
  obj["personality"] = Json::string(self.personality)
  obj["experimentalRawEvents"] = self.experimental_raw_events.to_json()
  obj["persistExtendedHistory"] = self.persist_extended_history.to_json()
  if self.dynamic_tools.length() > 0 {
    obj["dynamicTools"] = Json::array(
      self.dynamic_tools.map(fn(t) { t.to_json() }),
    )
  }
  Json::object(obj)
}

///|
/// Thread start response
pub(all) struct CodexThreadStartResponse {
  thread : CodexThread?
} derive(Show, Eq)

///|
pub fn CodexThreadStartResponse::from_json(
  json : Json,
) -> CodexThreadStartResponse? {
  match json {
    { "thread": thread_json, .. } =>
      Some({ thread: CodexThread::from_json(thread_json) })
    _ => Some({ thread: None })
  }
}

///|
/// Thread information
pub(all) struct CodexThread {
  id : String
} derive(Show, Eq)

///|
pub fn CodexThread::from_json(json : Json) -> CodexThread? {
  match json {
    { "id": String(id), .. } => Some({ id, })
    _ => None
  }
}

///|
/// Sandbox configuration
pub(all) struct CodexSandboxConfig {
  kind : String // "none", "docker", etc.
  image : String?
} derive(Show, Eq)

///|
pub fn CodexSandboxConfig::to_json(self : CodexSandboxConfig) -> Json {
  let obj : Map[String, Json] = {}
  obj["kind"] = Json::string(self.kind)
  match self.image {
    Some(image) => obj["image"] = Json::string(image)
    None => ()
  }
  Json::object(obj)
}

///|
pub fn CodexSandboxConfig::none() -> CodexSandboxConfig {
  { kind: "none", image: None }
}

// =============================================================================
// Turn Management
// =============================================================================

///|
/// Turn start request parameters
pub(all) struct CodexTurnStartParams {
  thread_id : String
  input : Array[CodexInputItem]
  model : String
  effort : String?
  personality : String?
  cwd : String
  approval_policy : String
  sandbox_policy : CodexSandboxPolicy?
} derive(Show, Eq)

///|
pub fn CodexTurnStartParams::to_json(self : CodexTurnStartParams) -> Json {
  let obj : Map[String, Json] = {}
  obj["threadId"] = Json::string(self.thread_id)
  obj["input"] = Json::array(self.input.map(fn(i) { i.to_json() }))
  obj["model"] = Json::string(self.model)
  match self.effort {
    Some(e) => obj["effort"] = Json::string(e)
    None => ()
  }
  match self.personality {
    Some(p) => obj["personality"] = Json::string(p)
    None => ()
  }
  obj["cwd"] = Json::string(self.cwd)
  obj["approvalPolicy"] = Json::string(self.approval_policy)
  match self.sandbox_policy {
    Some(policy) => obj["sandboxPolicy"] = policy.to_json()
    None => ()
  }
  Json::object(obj)
}

///|
/// Turn start response
pub(all) struct CodexTurnStartResponse {
  turn : CodexTurn?
} derive(Show, Eq)

///|
pub fn CodexTurnStartResponse::from_json(
  json : Json,
) -> CodexTurnStartResponse? {
  match json {
    { "turn": turn_json, .. } => Some({ turn: CodexTurn::from_json(turn_json) })
    _ => Some({ turn: None })
  }
}

///|
/// Turn information
pub(all) struct CodexTurn {
  id : String
} derive(Show, Eq)

///|
pub fn CodexTurn::from_json(json : Json) -> CodexTurn? {
  match json {
    { "id": String(id), .. } => Some({ id, })
    _ => None
  }
}

///|
/// Input item for turn
pub(all) struct CodexInputItem {
  kind : String // "text"
  text : String
  text_elements : Array[Json]
} derive(Show, Eq)

///|
pub fn CodexInputItem::to_json(self : CodexInputItem) -> Json {
  {
    "type": self.kind,
    "text": self.text,
    "text_elements": Json::array(self.text_elements),
  }
}

///|
pub fn CodexInputItem::text(content : String) -> CodexInputItem {
  { kind: "text", text: content, text_elements: [] }
}

///|
/// Sandbox policy for turn (matches Codex TurnStartParams.sandboxPolicy shape)
pub(all) struct CodexSandboxPolicy {
  sandbox_type : String // "none", "workspaceWrite", "fullAccess"
  writable_roots : Array[String]
  read_only_access : CodexReadOnlyAccess?
  network_access : Bool
} derive(Show, Eq)

///|
/// Read-only access configuration
pub(all) struct CodexReadOnlyAccess {
  access_type : String // "fullAccess", "workspaceOnly", "none"
} derive(Show, Eq)

///|
pub fn CodexReadOnlyAccess::to_json(self : CodexReadOnlyAccess) -> Json {
  { "type": self.access_type }
}

///|
pub fn CodexSandboxPolicy::to_json(self : CodexSandboxPolicy) -> Json {
  let obj : Map[String, Json] = {}
  obj["type"] = Json::string(self.sandbox_type)
  if self.writable_roots.length() > 0 {
    obj["writableRoots"] = Json::array(
      self.writable_roots.map(fn(p) { Json::string(p) }),
    )
  }
  match self.read_only_access {
    Some(roa) => obj["readOnlyAccess"] = roa.to_json()
    None => ()
  }
  obj["networkAccess"] = self.network_access.to_json()
  Json::object(obj)
}

///|
pub fn CodexSandboxPolicy::none() -> CodexSandboxPolicy {
  {
    sandbox_type: "none",
    writable_roots: [],
    read_only_access: None,
    network_access: false,
  }
}

///|
pub fn CodexSandboxPolicy::workspace_write(
  writable_roots : Array[String],
) -> CodexSandboxPolicy {
  {
    sandbox_type: "workspaceWrite",
    writable_roots,
    read_only_access: Some({ access_type: "fullAccess" }),
    network_access: false,
  }
}

///|
pub fn CodexSandboxPolicy::full_access() -> CodexSandboxPolicy {
  {
    sandbox_type: "fullAccess",
    writable_roots: [],
    read_only_access: Some({ access_type: "fullAccess" }),
    network_access: true,
  }
}

// =============================================================================
// Dynamic Tools
// =============================================================================

///|
/// Dynamic tool definition
pub(all) struct CodexDynamicTool {
  name : String
  description : String
  schema : Json
} derive(Show, Eq)

///|
pub fn CodexDynamicTool::to_json(self : CodexDynamicTool) -> Json {
  {
    "name": self.name,
    "description": self.description,
    "inputSchema": self.schema,
  }
}

///|
pub fn CodexDynamicTool::from_tool_definition(
  tool : @types.ToolDefinition,
) -> CodexDynamicTool {
  { name: tool.name, description: tool.description, schema: tool.parameters }
}

// =============================================================================
// Events
// =============================================================================

///|
/// Codex event types
pub(all) enum CodexEventType {
  SessionConfigured
  TaskStarted
  TaskComplete
  TokenCount
  AgentMessage
  AgentMessageDelta
  AgentMessageCompleted
  AgentMessageContentDelta
  TokenUsageUpdated
  RateLimitsUpdated
  TurnInputRequired
  ItemStarted
  ItemCompleted
  UserMessage
  Unknown(String)
} derive(Show, Eq)

///|
pub fn CodexEventType::from_string(s : String) -> CodexEventType {
  match s {
    "session_configured" => SessionConfigured
    "task_started" => TaskStarted
    "task_complete" => TaskComplete
    "token_count" => TokenCount
    "agent_message" => AgentMessage
    "agent_message_delta" => AgentMessageDelta
    "agent_message_completed" => AgentMessageCompleted
    "agent_message_content_delta" => AgentMessageContentDelta
    "token_usage_updated" => TokenUsageUpdated
    "rate_limits_updated" => RateLimitsUpdated
    "turn_input_required" => TurnInputRequired
    "item_started" => ItemStarted
    "item_completed" => ItemCompleted
    "user_message" => UserMessage
    other => Unknown(other)
  }
}

///|
/// Codex event message
pub(all) struct CodexEvent {
  event_type : CodexEventType
  timestamp : UInt64
  thread_id : String?
  turn_id : String?
  session_id : String?
  message : String?
  token_usage : CodexTokenUsage?
  rate_limits : Json?
} derive(Show, Eq)

///|
/// Token usage information
pub(all) struct CodexTokenUsage {
  input_tokens : Int
  output_tokens : Int
  total_tokens : Int
  cached_input_tokens : Int
  reasoning_output_tokens : Int
} derive(Show, Eq)

///|
pub fn CodexTokenUsage::from_json(json : Json) -> CodexTokenUsage? {
  // Format 1: thread/tokenUsage/updated (camelCase with nested total)
  match json {
    {
      "total": {
        "inputTokens": Number(input, ..),
        "outputTokens": Number(output, ..),
        "totalTokens": Number(total, ..),
        ..
      },
      ..
    } => {
      let cached = match json {
        { "total": { "cachedInputTokens": Number(c, ..), .. }, .. } =>
          c.to_int()
        _ => 0
      }
      let reasoning = match json {
        { "total": { "reasoningOutputTokens": Number(r, ..), .. }, .. } =>
          r.to_int()
        _ => 0
      }
      return Some({
        input_tokens: input.to_int(),
        output_tokens: output.to_int(),
        total_tokens: total.to_int(),
        cached_input_tokens: cached,
        reasoning_output_tokens: reasoning,
      })
    }
    _ => ()
  }
  // Format 2: codex/event/token_count (snake_case with total_token_usage)
  match json {
    {
      "info": {
        "total_token_usage": {
          "input_tokens": Number(input, ..),
          "output_tokens": Number(output, ..),
          "total_tokens": Number(total, ..),
          ..
        },
        ..
      },
      ..
    } => {
      let cached = match json {
        {
          "info": {
            "total_token_usage": { "cached_input_tokens": Number(c, ..), .. },
            ..
          },
          ..
        } => c.to_int()
        _ => 0
      }
      let reasoning = match json {
        {
          "info": {
            "total_token_usage": {
              "reasoning_output_tokens": Number(r, ..),
              ..
            },
            ..
          },
          ..
        } => r.to_int()
        _ => 0
      }
      return Some({
        input_tokens: input.to_int(),
        output_tokens: output.to_int(),
        total_tokens: total.to_int(),
        cached_input_tokens: cached,
        reasoning_output_tokens: reasoning,
      })
    }
    _ => ()
  }
  // Format 3: flat structure
  match json {
    {
      "inputTokens": Number(input, ..),
      "outputTokens": Number(output, ..),
      "totalTokens": Number(total, ..),
      ..
    } => {
      let cached = match json {
        { "cachedInputTokens": Number(c, ..), .. } => c.to_int()
        _ => 0
      }
      let reasoning = match json {
        { "reasoningOutputTokens": Number(r, ..), .. } => r.to_int()
        _ => 0
      }
      Some({
        input_tokens: input.to_int(),
        output_tokens: output.to_int(),
        total_tokens: total.to_int(),
        cached_input_tokens: cached,
        reasoning_output_tokens: reasoning,
      })
    }
    _ => None
  }
}

// =============================================================================
// Turn Result
// =============================================================================

///|
/// Turn completion result
pub(all) struct CodexTurnResult {
  id : String
  status : CodexTurnStatus
  error : String?
} derive(Show, Eq)

///|
/// Turn status
pub(all) enum CodexTurnStatus {
  InProgress
  Completed
  Interrupted
  Failed
} derive(Show, Eq)

///|
pub fn CodexTurnStatus::from_string(s : String) -> CodexTurnStatus {
  match s {
    "inProgress" => InProgress
    "completed" => Completed
    "interrupted" => Interrupted
    "failed" => Failed
    _ => Failed
  }
}

// =============================================================================
// Approval Requests
// =============================================================================

///|
/// Approval decision
pub(all) enum CodexApprovalDecision {
  AcceptForSession
  AcceptOnce
  Reject
} derive(Show, Eq)

///|
pub fn CodexApprovalDecision::to_string(self : CodexApprovalDecision) -> String {
  match self {
    AcceptForSession => "acceptForSession"
    AcceptOnce => "acceptOnce"
    Reject => "reject"
  }
}

///|
pub fn CodexApprovalDecision::to_json(self : CodexApprovalDecision) -> Json {
  { "decision": self.to_string() }
}

// =============================================================================
// Configuration
// =============================================================================

///|
/// Codex app-server configuration
pub(all) struct CodexConfig {
  command : String
  approval_policy : String?
  thread_sandbox : String?
  turn_sandbox_policy : String?
  turn_timeout_ms : Int
  read_timeout_ms : Int
  stall_timeout_ms : Int
} derive(Show, Eq, ToJson, FromJson)

///|
pub fn CodexConfig::default() -> CodexConfig {
  {
    command: "codex app-server",
    approval_policy: Some("never"),
    thread_sandbox: None,
    turn_sandbox_policy: None,
    turn_timeout_ms: 3600000, // 1 hour
    read_timeout_ms: 5000,
    stall_timeout_ms: 300000, // 5 minutes
  }
}

// =============================================================================
// Request Builders
// =============================================================================

///|
/// Build initialize request
pub fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
) -> CodexRpcRequest {
  let params : CodexInitializeParams = {
    client_info: { name: client_name, version: client_version },
    capabilities: { experimental_api: true },
  }
  { id: Some(id), rpc_method: "initialize", params: Some(params.to_json()) }
}

///|
/// Build thread/start request
pub fn build_thread_start_request(
  id : Int,
  model : String,
  cwd : String,
  approval_policy : String,
  dynamic_tools : Array[CodexDynamicTool],
) -> CodexRpcRequest {
  let params : CodexThreadStartParams = {
    model,
    cwd,
    approval_policy,
    sandbox: None,
    service_name: "llm_interop",
    personality: "pragmatic",
    experimental_raw_events: false,
    persist_extended_history: false,
    dynamic_tools,
  }
  { id: Some(id), rpc_method: "thread/start", params: Some(params.to_json()) }
}

///|
/// Build turn/start request
pub fn build_turn_start_request(
  id : Int,
  thread_id : String,
  prompt : String,
  model : String,
  effort : String?,
  cwd : String,
  approval_policy : String,
) -> CodexRpcRequest {
  let params : CodexTurnStartParams = {
    thread_id,
    input: [CodexInputItem::text(prompt)],
    model,
    effort,
    personality: None,
    cwd,
    approval_policy,
    sandbox_policy: None,
  }
  { id: Some(id), rpc_method: "turn/start", params: Some(params.to_json()) }
}

///|
/// Build initialized notification
pub fn build_initialized_notification() -> CodexRpcRequest {
  { id: None, rpc_method: "initialized", params: Some({}) }
}

///|
/// Build approval response
pub fn build_approval_response(
  id : Int,
  decision : CodexApprovalDecision,
) -> Json {
  { "id": id, "result": decision.to_json() }
}

///|
/// Build model/list request
pub fn build_model_list_request(
  id : Int,
  limit : Int,
  include_hidden : Bool,
) -> CodexRpcRequest {
  let params : Map[String, Json] = {}
  params["limit"] = Json::number(limit.to_double())
  params["includeHidden"] = include_hidden.to_json()
  { id: Some(id), rpc_method: "model/list", params: Some(Json::object(params)) }
}

// =============================================================================
// Model List Types
// =============================================================================

///|
/// Model information from model/list response
pub(all) struct CodexModelInfo {
  id : String
  model : String
  display_name : String
  hidden : Bool
  default_reasoning_effort : String?
  supported_reasoning_efforts : Array[CodexReasoningEffort]
  input_modalities : Array[String]
  is_default : Bool
} derive(Show, Eq)

///|
/// Reasoning effort option
pub(all) struct CodexReasoningEffort {
  reasoning_effort : String
  description : String
} derive(Show, Eq)

///|
pub fn CodexModelInfo::from_json(json : Json) -> CodexModelInfo? {
  match json {
    { "id": String(id), "model": String(model), .. } => {
      let display_name = match json {
        { "displayName": String(dn), .. } => dn
        _ => model
      }
      let hidden = match json {
        { "hidden": True, .. } => true
        _ => false
      }
      let default_effort = match json {
        { "defaultReasoningEffort": String(e), .. } => Some(e)
        _ => None
      }
      let efforts : Array[CodexReasoningEffort] = []
      match json {
        { "supportedReasoningEfforts": Array(arr), .. } =>
          for item in arr {
            match item {
              {
                "reasoning_effort": String(re),
                "description": String(desc),
                ..
              } => efforts.push({ reasoning_effort: re, description: desc })
              _ => ()
            }
          }
        _ => ()
      }
      let modalities : Array[String] = []
      match json {
        { "inputModalities": Array(arr), .. } =>
          for item in arr {
            match item {
              String(m) => modalities.push(m)
              _ => ()
            }
          }
        _ => ()
      }
      let is_default = match json {
        { "isDefault": True, .. } => true
        _ => false
      }
      Some({
        id,
        model,
        display_name,
        hidden,
        default_reasoning_effort: default_effort,
        supported_reasoning_efforts: efforts,
        input_modalities: modalities,
        is_default,
      })
    }
    _ => None
  }
}

///|
/// Parse model/list response data array
pub fn parse_model_list_response(json : Json) -> Array[CodexModelInfo] {
  let models : Array[CodexModelInfo] = []
  match json {
    { "data": Array(items), .. } =>
      for item in items {
        match CodexModelInfo::from_json(item) {
          Some(info) => models.push(info)
          None => ()
        }
      }
    _ => ()
  }
  models
}
