///|
/// MCP (Model Context Protocol) — pure protocol layer
///
/// Uses src/jsonrpc/ for JSON-RPC 2.0 envelope construction.
/// Application-agnostic — no knowledge of any specific server implementation.
/// It provides only:
///   - MCP type definitions (tool definitions, call results, content items)
///   - MCP-specific request builders (initialize, tools/list, tools/call)
///   - MCP-specific response parsers

// =============================================================================
// Types
// =============================================================================

///|
/// Tool definition from tools/list response
pub(all) struct McpToolDefinition {
  name : String
  description : String
  input_schema : Json
} derive(Show, Eq)

///|
pub fn McpToolDefinition::from_json(json : Json) -> McpToolDefinition? {
  match json {
    { "name": String(name), .. } => {
      let description = match json {
        { "description": String(d), .. } => d
        _ => ""
      }
      let input_schema = match json {
        { "inputSchema": schema, .. } => schema
        _ => Json::object({})
      }
      Some({ name, description, input_schema })
    }
    _ => None
  }
}

///|
/// Result from tools/call response
pub(all) struct McpToolCallResult {
  content : Array[McpContentItem]
  is_error : Bool
} derive(Show, Eq)

///|
/// Content item within a tools/call result
pub(all) struct McpContentItem {
  kind : String // "text", "image", "resource"
  text : String
} derive(Show, Eq)

///|
pub fn McpContentItem::from_json(json : Json) -> McpContentItem? {
  match json {
    { "type": String(kind), .. } => {
      let text = match json {
        { "text": String(t), .. } => t
        _ => ""
      }
      Some({ kind, text })
    }
    _ => None
  }
}

// =============================================================================
// Request Builders (delegate to @jsonrpc for envelope)
// =============================================================================

///|
/// Build MCP initialize request
pub fn build_initialize_request(
  id : Int,
  client_name : String,
  client_version : String,
) -> String {
  let params : Map[String, Json] = {}
  params["protocolVersion"] = Json::string("2025-03-26")
  params["capabilities"] = Json::object({})
  let client_info : Map[String, Json] = {}
  client_info["name"] = Json::string(client_name)
  client_info["version"] = Json::string(client_version)
  params["clientInfo"] = Json::object(client_info)
  @jsonrpc.build_request(id, "initialize", Some(Json::object(params)))
}

///|
/// Build MCP initialized notification (no id, no response expected)
pub fn build_initialized_notification() -> String {
  @jsonrpc.build_notification("notifications/initialized", None)
}

///|
/// Build MCP tools/list request
pub fn build_tools_list_request(id : Int) -> String {
  @jsonrpc.build_request(id, "tools/list", None)
}

///|
/// Build MCP tools/call request
pub fn build_tools_call_request(
  id : Int,
  tool_name : String,
  arguments : Json,
) -> String {
  let params : Map[String, Json] = {}
  params["name"] = Json::string(tool_name)
  params["arguments"] = arguments
  @jsonrpc.build_request(id, "tools/call", Some(Json::object(params)))
}

// =============================================================================
// Response Parsers
// =============================================================================

///|
/// Parse tools from tools/list response
pub fn parse_tools_list_response(json : Json) -> Array[McpToolDefinition] {
  let tools : Array[McpToolDefinition] = []
  match json {
    { "result": { "tools": Array(arr), .. }, .. } =>
      for item in arr {
        match McpToolDefinition::from_json(item) {
          Some(t) => tools.push(t)
          None => ()
        }
      }
    _ => ()
  }
  tools
}

///|
/// Parse tools/call result from response
pub fn parse_tools_call_result(json : Json) -> McpToolCallResult? {
  match json {
    { "result": result, .. } => {
      let is_error = match result {
        { "isError": True, .. } => true
        _ => false
      }
      let content : Array[McpContentItem] = []
      match result {
        { "content": Array(arr), .. } =>
          for item in arr {
            match McpContentItem::from_json(item) {
              Some(c) => content.push(c)
              None => ()
            }
          }
        _ => ()
      }
      Some({ content, is_error })
    }
    _ => None
  }
}

///|
/// Extract text content from an MCP tools/call result, joining all text items.
pub fn extract_text_content(result : McpToolCallResult) -> String {
  let buf = StringBuilder::new()
  for item in result.content {
    if item.kind == "text" {
      if buf.to_string().length() > 0 {
        buf.write_string("\n")
      }
      buf.write_string(item.text)
    }
  }
  buf.to_string()
}
