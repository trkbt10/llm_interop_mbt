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
    @types.ModelMessage::User(content~, name~, content_parts~) =>
      match content_parts {
        Some(parts) => {
          let anthropic_content = content_parts_to_anthropic_json(parts)
          match name {
            Some(n) =>
              {
                "role": "user",
                "content": Json::array(anthropic_content),
                "name": n,
              }
            None =>
              { "role": "user", "content": Json::array(anthropic_content) }
          }
        }
        None =>
          match name {
            Some(n) => { "role": "user", "content": content, "name": n }
            None => { "role": "user", "content": content }
          }
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
pub fn messages_to_json(messages : Array[@types.ModelMessage]) -> Array[Json] {
  let result : Array[Json] = []
  for msg in messages {
    match msg {
      @types.ModelMessage::System(_) => ()
      @types.ModelMessage::User(content~, content_parts~, ..) =>
        match content_parts {
          Some(parts) =>
            result.push({
              "role": "user",
              "content": Json::array(content_parts_to_anthropic_json(parts)),
            })
          None => result.push({ "role": "user", "content": content })
        }
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

///|
/// Convert ContentPart array to Anthropic content blocks format.
/// Ref: docs/upstream/anthropic-messages-api.md:80 — TextBlockParam
/// Ref: docs/upstream/anthropic-messages-api.md:193 — ImageBlockParam
/// Ref: docs/upstream/anthropic-messages-api.md:250 — DocumentBlockParam
fn content_parts_to_anthropic_json(
  parts : Array[@types.ContentPart],
) -> Array[Json] {
  let result : Array[Json] = []
  for part in parts {
    match part {
      // Ref: docs/upstream/anthropic-messages-api.md:80
      //   TextBlockParam = object { text, type, cache_control, citations }
      @types.ContentPart::Text(text) =>
        result.push({ "type": "text", "text": text })
      // Ref: docs/upstream/anthropic-messages-api.md:193
      //   ImageBlockParam = object { source, type, cache_control }
      @types.ContentPart::ImageUrl(url~, ..) => {
        let source : Map[String, Json] = {
          "type": Json::string("url"),
          "url": Json::string(url),
        }
        result.push({ "type": "image", "source": Json::object(source) })
      }
      // Ref: docs/upstream/anthropic-messages-api.md:193 — ImageBlockParam base64 source variant
      @types.ContentPart::ImageBase64(data~, media_type~) => {
        let source : Map[String, Json] = {
          "type": Json::string("base64"),
          "media_type": Json::string(media_type),
          "data": Json::string(data),
        }
        result.push({ "type": "image", "source": Json::object(source) })
      }
      // Inference: docs/upstream/anthropic-messages-api.md:74-80,193-250
      // documents text/image/document request blocks for MessageParam.content;
      // audio input blocks are not part of the published ContentBlockParam union.
      @types.ContentPart::Audio(..) => ()
      // Ref: docs/upstream/anthropic-messages-api.md:250
      //   DocumentBlockParam = object { source, type, cache_control, context, citations, title }
      @types.ContentPart::Document(data~, media_type~, title~) => {
        let source : Map[String, Json] = {
          "type": Json::string("base64"),
          "media_type": Json::string(media_type),
          "data": Json::string(data),
        }
        let doc : Map[String, Json] = {
          "type": Json::string("document"),
          "source": Json::object(source),
        }
        match title {
          Some(t) => doc["title"] = Json::string(t)
          None => ()
        }
        result.push(Json::object(doc))
      }
      // Ref: docs/upstream/anthropic-messages-api.md:250 — DocumentBlockParam file source variant
      // Ref: docs/upstream/anthropic-files-api.md — Files API file_id reference
      @types.ContentPart::FileRef(file_id~, ..) =>
        result.push({
          "type": "document",
          "source": { "type": "file", "file_id": file_id },
        })
      // Inference: docs/upstream/anthropic-messages-api.md:74-80,193-250
      // documents text/image/document request blocks for MessageParam.content;
      // video input blocks are not part of the published ContentBlockParam union.
      @types.ContentPart::Video(..) => ()
    }
  }
  result
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
    "name": @types.web_search_tool_name(),
    "description": @types.web_search_tool_description(),
    "input_schema": @types.web_search_tool_parameters_schema(),
  }
}

///|
/// Convert tool definition array to Anthropic format JSON array
pub fn tools_to_json(tools : Array[@types.ToolDefinition]) -> Array[Json] {
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
  // Ref: docs/upstream/anthropic-messages-api.md:13-21 — max_tokens is a
  // required request body field.
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
      // Extract text response and structured content parts
      match content {
        Array(blocks) => {
          let text = StringBuilder::new()
          let content_parts : Array[@types.ResponseContentPart] = []
          let mut has_non_text = false
          for block in blocks {
            match block {
              { "type": String("text"), "text": String(t), .. } => {
                if text.to_string().length() > 0 {
                  text.write_char('\n')
                }
                text.write_string(t)
                content_parts.push(@types.ResponseContentPart::OutputText(t))
              }
              // ThinkingBlock: {"type":"thinking","thinking":"..."}
              // Ref: docs/upstream/anthropic-messages-api.md:3971-3979 — ThinkingBlock
              { "type": String("thinking"), "thinking": String(t), .. } => {
                content_parts.push(@types.ResponseContentPart::Thinking(text=t))
                has_non_text = true
              }
              // RedactedThinkingBlock: {"type":"redacted_thinking","data":"..."}
              // Ref: docs/upstream/anthropic-messages-api.md:3981 — RedactedThinkingBlock
              { "type": String("redacted_thinking"), "data": String(d), .. } => {
                content_parts.push(
                  @types.ResponseContentPart::RedactedThinking(data=d),
                )
                has_non_text = true
              }
              // CodeExecutionToolResultBlock: {"type":"code_execution_tool_result","content":{"stdout":"...","stderr":"...","return_code":N}}
              // Ref: docs/upstream/anthropic-messages-api.md:1911-1977 — CodeExecutionToolResultBlockParam
              // Ref: docs/upstream/anthropic-code-execution-tool.md:1796-1802 — stdout/stderr/return_code example
              // Ref: docs/upstream/anthropic-messages-api.md:1933-1947 —
              // content may carry stdout, stderr, and return_code together.
              {
                "type": String("code_execution_tool_result"),
                "content": content_obj,
                ..
              } => {
                let stdout = match content_obj {
                  { "stdout": String(s), .. } => s
                  _ => ""
                }
                let stderr = match content_obj {
                  { "stderr": String(s), .. } => s
                  _ => ""
                }
                let rc = match content_obj {
                  { "return_code": Number(n, ..), .. } => n.to_int()
                  _ => -1
                }
                let outcome = if rc == 0 { "success" } else { "failed" }
                // Combine stdout and stderr; include both when available
                let output = if stdout.length() > 0 && stderr.length() > 0 {
                  "\{stdout}\n[stderr]\n\{stderr}"
                } else if stderr.length() > 0 {
                  "[stderr]\n\{stderr}"
                } else {
                  stdout
                }
                content_parts.push(
                  @types.ResponseContentPart::CodeResult(outcome~, output~),
                )
                has_non_text = true
              }
              _ => ()
            }
          }
          if has_non_text {
            @types.ModelResponse::RichText(
              @types.RichTextResponse::new(
                content=text.to_string(),
                content_parts=Some(content_parts),
              ),
            )
          } else {
            @types.ModelResponse::Text(text.to_string())
          }
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
pub fn parse_tool_calls(content : Json) -> Array[@types.ToolCallRequest] {
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
