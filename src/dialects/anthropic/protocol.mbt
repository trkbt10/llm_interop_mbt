///|
/// Anthropic Messages API protocol

// =============================================================================
// Message Conversion
// =============================================================================

///|
/// Convert ModelMessage to JSON (Anthropic format)
pub fn message_to_json(message : @types.ModelMessage) -> Json {
  match message {
    @types.ModelMessage::System(content) =>
      { "role": "system", "content": content }
    @types.ModelMessage::User(content~, name~) =>
      match name {
        Some(n) => { "role": "user", "content": content, "name": n }
        None => { "role": "user", "content": content }
      }
    @types.ModelMessage::Assistant(content~, tool_calls~) =>
      match tool_calls {
        Some(calls) => {
          let tool_use : Array[Json] = []
          for call in calls {
            tool_use.push({
              "type": "tool_use",
              "id": call.id,
              "name": call.name,
              "input": call.arguments,
            })
          }
          { "role": "assistant", "content": Json::array(tool_use) }
        }
        None => { "role": "assistant", "content": content }
      }
    @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
      {
        "role": "user",
        "content": Json::array([
          {
            "type": "tool_result",
            "tool_use_id": tool_call_id,
            "content": content,
          },
        ]),
      }
  }
}

///|
/// Convert message array to Anthropic format JSON array (excludes System messages)
pub fn messages_to_json(
  messages : Array[@types.ModelMessage],
) -> Array[Json] {
  let result : Array[Json] = []
  for msg in messages {
    match msg {
      @types.ModelMessage::System(_) => ()
      @types.ModelMessage::User(content~, ..) =>
        result.push({ "role": "user", "content": content })
      @types.ModelMessage::Assistant(content~, tool_calls~) =>
        match tool_calls {
          Some(calls) if calls.length() > 0 => {
            let content_blocks : Array[Json] = []
            if content.length() > 0 {
              content_blocks.push({ "type": "text", "text": content })
            }
            for call in calls {
              content_blocks.push({
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                "input": call.arguments,
              })
            }
            result.push({
              "role": "assistant",
              "content": Json::array(content_blocks),
            })
          }
          _ => result.push({ "role": "assistant", "content": content })
        }
      @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
        result.push({
          "role": "user",
          "content": Json::array([
            {
              "type": "tool_result",
              "tool_use_id": tool_call_id,
              "content": content,
            },
          ]),
        })
    }
  }
  result
}

///|
/// Extract system message from message array
pub fn extract_system_message(messages : Array[@types.ModelMessage]) -> String {
  for msg in messages {
    match msg {
      @types.ModelMessage::System(content) => return content
      _ => ()
    }
  }
  ""
}

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to JSON (Anthropic format)
pub fn tool_to_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "name": tool.name,
        "description": tool.description,
        "input_schema": tool.parameters,
      }
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
fn web_search_tool_to_json() -> Json {
  {
    "name": "web_search",
    "description": "Search the web",
    "input_schema": {
      "type": "object",
      "properties": { "query": { "type": "string" } },
      "required": Json::array([Json::string("query")]),
    },
  }
}

///|
/// Convert tool definition array to Anthropic format JSON array
pub fn tools_to_json(
  tools : Array[@types.ToolDefinition],
) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_json(tool))
  }
  result
}

// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build Anthropic request body
pub fn build_body(
  model : String,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  max_tokens? : Int? = None,
  system? : String = "",
  temperature? : Double? = None,
) -> Json {
  let system_msg = if system.length() > 0 {
    system
  } else {
    extract_system_message(messages)
  }
  let msgs = messages_to_json(messages)
  // Anthropic API requires max_tokens
  let effective_max_tokens = max_tokens.unwrap_or(8192)
  let mut body : Json = {
    "model": model,
    "max_tokens": effective_max_tokens,
    "messages": Json::array(msgs),
  }
  if system_msg.length() > 0 {
    body = @utils.set_json_field(body, "system", Json::string(system_msg))
  }
  match temperature {
    Some(temp) =>
      body = @utils.set_json_field(body, "temperature", Json::number(temp))
    None => ()
  }
  if tools.length() > 0 {
    body = @utils.set_json_field(
      body,
      "tools",
      Json::array(tools_to_json(tools)),
    )
  }
  body
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse Anthropic response
pub fn parse_response(response_json : Json) -> @types.ModelResponse {
  match response_json {
    { "content": content, "stop_reason": String(stop_reason), .. } => {
      // Check for tool use
      if stop_reason == "tool_use" {
        let tool_calls = parse_tool_calls(content)
        if tool_calls.length() > 0 {
          return @types.ModelResponse::ToolCalls(tool_calls)
        }
      }
      // Extract text response
      match content {
        Array(blocks) => {
          let text = StringBuilder::new()
          for block in blocks {
            match block {
              { "type": String("text"), "text": String(t), .. } => {
                if text.to_string().length() > 0 {
                  text.write_char('\n')
                }
                text.write_string(t)
              }
              _ => ()
            }
          }
          @types.ModelResponse::Text(text.to_string())
        }
        _ => @types.ModelResponse::ModelError("Invalid content format")
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
  }
}

///|
/// Parse tool calls from Anthropic response
pub fn parse_tool_calls(
  content : Json,
) -> Array[@types.ToolCallRequest] {
  let result : Array[@types.ToolCallRequest] = []
  match content {
    Array(items) =>
      for item in items {
        match item {
          {
            "type": String("tool_use"),
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } =>
            result.push(
              @types.ToolCallRequest::new(id~, name~, arguments=input),
            )
          _ => ()
        }
      }
    _ => ()
  }
  result
}
