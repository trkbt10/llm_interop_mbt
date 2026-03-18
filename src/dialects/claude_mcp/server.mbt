///|
/// MCP server-side responses and request parsing
///
/// This is the inverse of session.mbt:
///   session.mbt: client side — we build requests TO `claude mcp serve`
///   server.mbt:  server side — we build responses AS an MCP server
///
/// Used by cmd/claude-mcp-server to serve MCP protocol to external clients
/// while proxying to LLM backends via the gateway.

// =============================================================================
// Server response builders
// =============================================================================

///|
/// Build MCP initialize response with server capabilities.
pub fn build_initialize_result(id : Int) -> String {
  let result : Map[String, Json] = {}
  result["protocolVersion"] = Json::string("2025-03-26")
  let server_info : Map[String, Json] = {}
  server_info["name"] = Json::string("llm_interop-mcp-server")
  server_info["version"] = Json::string("0.1.0")
  result["serverInfo"] = Json::object(server_info)
  result["capabilities"] = Json::object({ "tools": Json::object({}) })
  @jsonrpc.build_response(Some(id), Json::object(result))
}

///|
/// Build MCP tools/list response from tool definitions.
pub fn build_tools_list_result(
  id : Int,
  tools : Array[@mcp.McpToolDefinition],
) -> String {
  let tool_jsons : Array[Json] = []
  for tool in tools {
    let obj : Map[String, Json] = {}
    obj["name"] = Json::string(tool.name)
    obj["description"] = Json::string(tool.description)
    obj["inputSchema"] = tool.input_schema
    tool_jsons.push(Json::object(obj))
  }
  let result : Map[String, Json] = {}
  result["tools"] = Json::array(tool_jsons)
  @jsonrpc.build_response(Some(id), Json::object(result))
}

///|
/// Build MCP tools/call success result with text content.
pub fn build_tools_call_result(
  id : Int,
  text : String,
  is_error : Bool,
) -> String {
  let content_item : Map[String, Json] = {}
  content_item["type"] = Json::string("text")
  content_item["text"] = Json::string(text)
  let result : Map[String, Json] = {}
  result["content"] = Json::array([Json::object(content_item)])
  if is_error {
    result["isError"] = true.to_json()
  }
  @jsonrpc.build_response(Some(id), Json::object(result))
}

///|
/// Build MCP ping response.
pub fn build_ping_result(id : Int) -> String {
  @jsonrpc.build_response(Some(id), Json::object({}))
}

// =============================================================================
// Server request parsers
// =============================================================================

///|
/// Parsed tools/call parameters
pub(all) struct ToolsCallParams {
  name : String
  arguments : Json
} derive(Show, Eq)

///|
/// Parse tools/call params from JSON-RPC params field.
pub fn parse_tools_call_params(params : Json?) -> ToolsCallParams? {
  let p = match params {
    Some(p) => p
    None => return None
  }
  match p {
    { "name": String(name), .. } => {
      let arguments = match p {
        { "arguments": args, .. } => args
        _ => Json::object({})
      }
      Some({ name, arguments })
    }
    _ => None
  }
}

///|
/// Extracted prompt arguments from tools/call arguments
pub(all) struct PromptArgs {
  prompt : String
  system : String
  max_tokens : Int
} derive(Show, Eq)

///|
/// Extract prompt-related arguments from tools/call arguments object.
pub fn extract_prompt_args(arguments : Json) -> PromptArgs {
  let prompt = match arguments {
    { "prompt": String(p), .. } => p
    _ => ""
  }
  let system = match arguments {
    { "system": String(s), .. } => s
    _ => ""
  }
  let max_tokens = match arguments {
    { "max_tokens": Number(n, ..), .. } => n.to_int()
    _ => 4096
  }
  { prompt, system, max_tokens }
}

// =============================================================================
// Tool definition builder from model config
// =============================================================================

///|
/// Input schema for LLM tool (prompt, system, max_tokens).
fn llm_input_schema() -> Json {
  let prompt_prop : Map[String, Json] = {}
  prompt_prop["type"] = Json::string("string")
  prompt_prop["description"] = Json::string("The prompt to send to the model")
  let system_prop : Map[String, Json] = {}
  system_prop["type"] = Json::string("string")
  system_prop["description"] = Json::string("Optional system prompt")
  let max_tokens_prop : Map[String, Json] = {}
  max_tokens_prop["type"] = Json::string("integer")
  max_tokens_prop["description"] = Json::string(
    "Maximum tokens in the response (default: 4096)",
  )
  let properties : Map[String, Json] = {}
  properties["prompt"] = Json::object(prompt_prop)
  properties["system"] = Json::object(system_prop)
  properties["max_tokens"] = Json::object(max_tokens_prop)
  let schema : Map[String, Json] = {}
  schema["type"] = Json::string("object")
  schema["properties"] = Json::object(properties)
  schema["required"] = Json::array([Json::string("prompt")])
  Json::object(schema)
}

///|
/// Build an MCP tool definition for a model.
pub fn model_to_mcp_tool(
  model_id : String,
  model_name : String,
  provider_id : String,
) -> @mcp.McpToolDefinition {
  {
    name: model_id,
    description: model_name + " (" + provider_id + ")",
    input_schema: llm_input_schema(),
  }
}

// =============================================================================
// Chat request construction (OpenAI format, for gateway transform pipeline)
// =============================================================================

///|
/// Build an OpenAI Chat Completions request body from prompt arguments.
/// The gateway transform pipeline will convert this to the target dialect
/// (Anthropic, Gemini, etc.) as needed via `prepare_upstream`.
pub fn build_chat_request(
  model : String,
  prompt : String,
  system : String,
  max_tokens : Int,
) -> String {
  let messages : Array[Json] = []
  if system != "" {
    let sys_msg : Map[String, Json] = {}
    sys_msg["role"] = Json::string("system")
    sys_msg["content"] = Json::string(system)
    messages.push(Json::object(sys_msg))
  }
  let user_msg : Map[String, Json] = {}
  user_msg["role"] = Json::string("user")
  user_msg["content"] = Json::string(prompt)
  messages.push(Json::object(user_msg))
  let obj : Map[String, Json] = {}
  obj["model"] = Json::string(model)
  obj["messages"] = Json::array(messages)
  obj["max_tokens"] = Json::number(max_tokens.to_double())
  obj["stream"] = false.to_json()
  Json::object(obj).stringify()
}

// =============================================================================
// Response extraction (from OpenAI-normalized response)
// =============================================================================

///|
/// Extract assistant content from a gateway-normalized (OpenAI format) response.
/// The gateway's `transform_response` normalizes all provider responses to
/// OpenAI format, so this always extracts from choices[0].message.content.
pub fn extract_assistant_content(response_body : String) -> String {
  let json = @json.parse(response_body) catch { _ => return response_body }
  match json {
    {
      "choices": [{ "message": { "content": String(content), .. }, .. }, ..],
      ..
    } => content
    _ => response_body
  }
}
