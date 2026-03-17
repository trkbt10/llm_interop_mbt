///|
/// `claude mcp serve` ↔ OpenAI Chat Completions transforms
///
/// Request: OpenAI messages → prompt extraction (for tool dispatch in cmd layer)
/// Response: MCP tools/call result → OpenAI Chat Completion response

// =============================================================================
// Request transform: OpenAI → prompt extraction
// =============================================================================

///|
/// Extract prompt from OpenAI Chat Completion request.
/// The cmd layer decides which `claude mcp serve` tool to invoke.
pub fn chat_request_to_prompt(
  body : String,
  _ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let model = match json {
    { "model": String(m), .. } => m
    _ => "claude-code-tools"
  }
  let messages = match json {
    { "messages": Array(msgs), .. } => msgs
    _ => return body
  }
  let prompt = build_prompt_from_messages(messages)
  let obj : Map[String, Json] = {}
  obj["prompt"] = Json::string(prompt)
  obj["model"] = Json::string(model)
  obj["messages"] = Json::array(messages)
  Json::object(obj).stringify()
}

///|
/// Build a prompt string from OpenAI messages (same logic as Codex).
fn build_prompt_from_messages(messages : Array[Json]) -> String {
  let mut system_msg = ""
  let mut last_user_msg = ""
  for msg in messages {
    match msg {
      { "role": String("system"), "content": String(text), .. } =>
        system_msg = text
      { "role": String("user"), "content": String(text), .. } =>
        last_user_msg = text
      { "role": String("user"), "content": Array(parts), .. } => {
        let buf = StringBuilder::new()
        for part in parts {
          match part {
            { "type": String("text"), "text": String(t), .. } => {
              if buf.to_string().length() > 0 {
                buf.write_string("\n")
              }
              buf.write_string(t)
            }
            _ => ()
          }
        }
        last_user_msg = buf.to_string()
      }
      _ => ()
    }
  }
  if system_msg != "" && last_user_msg != "" {
    system_msg + "\n\n" + last_user_msg
  } else if last_user_msg != "" {
    last_user_msg
  } else {
    system_msg
  }
}

// =============================================================================
// Response transform: MCP result → OpenAI Chat Completion
// =============================================================================

///|
/// Transform `claude mcp serve` tools/call result into OpenAI Chat Completion.
pub fn tools_result_to_chat(body : String) -> String {
  let json = @json.parse(body) catch {
    _ => return build_simple_chat_response(body)
  }
  match @mcp.parse_tools_call_result(json) {
    Some(result) => {
      let content = @mcp.extract_text_content(result)
      if result.is_error {
        build_error_chat_response(content)
      } else {
        build_simple_chat_response(content)
      }
    }
    None => build_simple_chat_response(body)
  }
}

///|
fn build_simple_chat_response(content : String) -> String {
  let message : Map[String, Json] = {}
  message["role"] = Json::string("assistant")
  message["content"] = Json::string(content)
  let choice : Map[String, Json] = {}
  choice["index"] = Json::number(0.0)
  choice["message"] = Json::object(message)
  choice["finish_reason"] = Json::string("stop")
  let usage : Map[String, Json] = {}
  usage["prompt_tokens"] = Json::number(0.0)
  usage["completion_tokens"] = Json::number(0.0)
  usage["total_tokens"] = Json::number(0.0)
  let result : Map[String, Json] = {}
  result["id"] = Json::string("claude-mcp-response")
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string("claude-code-tools")
  result["choices"] = Json::array([Json::object(choice)])
  result["usage"] = Json::object(usage)
  Json::object(result).stringify()
}

///|
fn build_error_chat_response(message : String) -> String {
  let err : Json = {
    "error": {
      "message": message,
      "type": "claude_mcp_error",
      "code": "tool_error",
    },
  }
  err.stringify()
}
