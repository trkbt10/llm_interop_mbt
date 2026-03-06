///|
/// OpenAI Chat Completions API protocol

// =============================================================================
// Message Conversion
// =============================================================================

///|
/// Convert ModelMessage to JSON (OpenAI Chat Completions format)
pub fn message_to_openai_json(message : @types.ModelMessage) -> Json {
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
          let tool_calls_json : Array[Json] = []
          for call in calls {
            tool_calls_json.push({
              "id": call.id,
              "type": "function",
              "function": {
                "name": call.name,
                "arguments": call.arguments.stringify(),
              },
            })
          }
          {
            "role": "assistant",
            "content": content,
            "tool_calls": Json::array(tool_calls_json),
          }
        }
        None => { "role": "assistant", "content": content }
      }
    @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
      { "role": "tool", "tool_call_id": tool_call_id, "content": content }
  }
}

///|
/// Convert message array to OpenAI Chat Completions format JSON array
pub fn messages_to_openai_json(
  messages : Array[@types.ModelMessage],
) -> Array[Json] {
  let result : Array[Json] = []
  for msg in messages {
    result.push(message_to_openai_json(msg))
  }
  result
}

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to JSON (OpenAI Chat Completions format)
pub fn tool_to_openai_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "type": "function",
        "function": {
          "name": tool.name,
          "description": tool.description,
          "parameters": tool.parameters,
        },
      }
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_openai_json()
  }
}

///|
fn web_search_tool_to_openai_json() -> Json {
  {
    "type": "function",
    "function": {
      "name": "web_search",
      "description": "Search the web",
      "parameters": {
        "type": "object",
        "properties": { "query": { "type": "string" } },
        "required": Json::array([Json::string("query")]),
      },
    },
  }
}

///|
/// Convert tool definition array to OpenAI Chat Completions format JSON array
pub fn tools_to_openai_json(
  tools : Array[@types.ToolDefinition],
) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_openai_json(tool))
  }
  result
}

// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build OpenAI Chat Completions request body
pub fn build_openai_chat_body(
  model : String,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  max_tokens? : Int? = None,
  temperature? : Double? = None,
) -> Json {
  let msgs = messages_to_openai_json(messages)
  let mut body : Json = { "model": model, "messages": Json::array(msgs) }
  match max_tokens {
    Some(max) =>
      body = @utils.set_json_field(
        body,
        "max_tokens",
        Json::number(max.to_double()),
      )
    None => ()
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
      Json::array(tools_to_openai_json(tools)),
    )
    body = @utils.set_json_field(body, "tool_choice", Json::string("auto"))
  }
  body
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse OpenAI Chat Completions response
pub fn parse_openai_chat_response(json : Json) -> @types.ModelResponse {
  match json {
    { "choices": Array(choices), .. } => {
      if choices.length() == 0 {
        return @types.ModelResponse::ModelError("No choices in response")
      }
      let choice = choices[0]
      match choice {
        { "message": message, "finish_reason": String(finish_reason), .. } => {
          // Check for tool calls
          if finish_reason == "tool_calls" {
            match message {
              { "tool_calls": tool_calls, .. } => {
                let calls = parse_openai_tool_calls(tool_calls)
                if calls.length() > 0 {
                  return @types.ModelResponse::ToolCalls(calls)
                }
              }
              _ => ()
            }
          }
          // Extract text response
          match message {
            { "content": String(content), .. } =>
              @types.ModelResponse::Text(content)
            { "content": Null, "tool_calls": tool_calls, .. } => {
              let calls = parse_openai_tool_calls(tool_calls)
              if calls.length() > 0 {
                @types.ModelResponse::ToolCalls(calls)
              } else {
                @types.ModelResponse::Text("")
              }
            }
            _ => @types.ModelResponse::ModelError("Invalid message format")
          }
        }
        _ => @types.ModelResponse::ModelError("Invalid choice format")
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
  }
}

///|
/// Parse tool calls from OpenAI response
pub fn parse_openai_tool_calls(
  tool_calls : Json,
) -> Array[@types.ToolCallRequest] {
  let result : Array[@types.ToolCallRequest] = []
  match tool_calls {
    Array(calls) =>
      for call in calls {
        match call {
          {
            "id": String(id),
            "function": {
              "name": String(name),
              "arguments": String(args_str),
              ..
            },
            ..
          } => {
            let arguments : Json = @json.parse(args_str) catch { _ => {} }
            result.push(@types.ToolCallRequest::new(id~, name~, arguments~))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result
}
