///|
/// JSON-RPC 2.0 — pure protocol layer
///
/// Application-agnostic — no knowledge of any higher-level protocol.
/// Provides only RFC 7540 2.0 types, builders, and parsers.

// =============================================================================
// Types
// =============================================================================

///|
/// JSON-RPC 2.0 request message
pub(all) struct RpcRequest {
  id : Int?
  rpc_method : String
  params : Json?
} derive(Show, Eq)

///|
/// JSON-RPC 2.0 response message
pub(all) struct RpcResponse {
  id : Int?
  result : Json?
  error : RpcError?
} derive(Show, Eq)

///|
/// JSON-RPC 2.0 error object
pub(all) struct RpcError {
  code : Int
  message : String
} derive(Show, Eq, ToJson, FromJson)

///|
/// A single step in a JSON-RPC message sequence.
/// The host runtime executes steps in order.
pub(all) struct RpcStep {
  /// Serialized JSON-RPC message
  message : String
  /// How the host handles this step
  kind : RpcStepKind
} derive(Show)

///|
pub(all) enum RpcStepKind {
  /// Send and expect a JSON-RPC response
  Request
  /// Send without expecting a response (notification)
  Notification
} derive(Show, Eq)

// =============================================================================
// Request Builders
// =============================================================================

///|
/// Build a JSON-RPC 2.0 request
pub fn build_request(id : Int, rpc_method : String, params : Json?) -> String {
  let obj : Map[String, Json] = {}
  obj["jsonrpc"] = Json::string("2.0")
  obj["id"] = Json::number(id.to_double())
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(p) => obj["params"] = p
    None => ()
  }
  Json::object(obj).stringify()
}

///|
/// Build a JSON-RPC 2.0 notification (no id, no response expected)
pub fn build_notification(rpc_method : String, params : Json?) -> String {
  let obj : Map[String, Json] = {}
  obj["jsonrpc"] = Json::string("2.0")
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(p) => obj["params"] = p
    None => ()
  }
  Json::object(obj).stringify()
}

// =============================================================================
// Response Builders
// =============================================================================

///|
/// Build a JSON-RPC 2.0 success response
pub fn build_response(id : Int?, result : Json) -> String {
  let obj : Map[String, Json] = {}
  obj["jsonrpc"] = Json::string("2.0")
  match id {
    Some(i) => obj["id"] = Json::number(i.to_double())
    None => ()
  }
  obj["result"] = result
  Json::object(obj).stringify()
}

///|
/// Build a JSON-RPC 2.0 error response
pub fn build_error_response(id : Int?, code : Int, message : String) -> String {
  let obj : Map[String, Json] = {}
  obj["jsonrpc"] = Json::string("2.0")
  match id {
    Some(i) => obj["id"] = Json::number(i.to_double())
    None => ()
  }
  obj["error"] = { "code": Json::number(code.to_double()), "message": message }
  Json::object(obj).stringify()
}

// =============================================================================
// Parsers
// =============================================================================

///|
/// Parses an `RpcRequest` from a JSON-RPC 2.0 JSON value.
pub fn RpcRequest::from_json(json : Json) -> RpcRequest? {
  match json {
    { "method": String(m), .. } => {
      let id = match json {
        { "id": Number(n, ..), .. } => Some(n.to_int())
        _ => None
      }
      let params = match json {
        { "params": p, .. } => Some(p)
        _ => None
      }
      Some({ id, rpc_method: m, params })
    }
    _ => None
  }
}

///|
/// Serializes this `RpcRequest` to a JSON-RPC 2.0 JSON value.
pub fn RpcRequest::to_json(self : RpcRequest) -> Json {
  let obj : Map[String, Json] = {}
  obj["jsonrpc"] = Json::string("2.0")
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
/// Parses an `RpcResponse` from a JSON-RPC 2.0 JSON value, handling both result and error cases.
pub fn RpcResponse::from_json(json : Json) -> RpcResponse? {
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
