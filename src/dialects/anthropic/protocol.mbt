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
      {
        "role": "assistant",
        "content": assistant_content_to_json(content, tool_calls),
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
        result.push({
          "role": "assistant",
          "content": assistant_content_to_json(content, tool_calls),
        })
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
      @types.ContentPart::Audio(..) =>
        result.push({
          "type": "text",
          "text": "[Audio input not supported by Anthropic Messages API]",
        })
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
      // Ref: docs/upstream/anthropic-files-api.md —
      // Anthropic documents use uploaded file IDs or inline bytes, not remote URLs.
      @types.ContentPart::FileUrl(url~) =>
        result.push({
          "type": "text",
          "text": "[Remote file URL input not supported by Anthropic Messages API; upload via Files API first] \{url}",
        })
      // Inference: docs/upstream/anthropic-messages-api.md:74-80,193-250
      // documents text/image/document request blocks for MessageParam.content;
      // video input blocks are not part of the published ContentBlockParam union.
      @types.ContentPart::Video(..) =>
        result.push({
          "type": "text",
          "text": "[Video input not supported by Anthropic Messages API]",
        })
    }
  }
  result
}

///|
fn assistant_content_to_json(
  content : String,
  tool_calls : Array[@types.ToolCallRequest]?,
) -> Json {
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
      Json::array(content_blocks)
    }
    _ => Json::string(content)
  }
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
    @types.ToolDefinitionKind::Builtin(builtin_type~, config~) =>
      build_builtin_tool_json(builtin_type, tool.name, config)
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
fn build_builtin_tool_json(
  type_ : String,
  name : String,
  config : Json,
) -> Json {
  let result : Map[String, Json] = { "type": Json::string(type_) }
  if name.length() > 0 {
    result["name"] = Json::string(name)
  }
  match config {
    Object(fields) =>
      for key, value in fields {
        result[key] = value
      }
    Null => ()
    _ =>
      abort(
        "Anthropic builtin tool config must be an object: " + config.stringify(),
      )
  }
  Json::object(result)
}

///|
fn web_search_tool_to_json() -> Json {
  build_builtin_tool_json(
    "web_search_20260209",
    @types.web_search_tool_name(),
    Json::object({}),
  )
}

///|
fn build_code_execution_input_part(
  name : String,
  input : Json,
) -> @types.ResponseContentPart? {
  match name {
    "code_execution" => {
      let code = match input {
        { "code": String(value), .. } => value
        _ =>
          abort(
            "Anthropic code_execution tool input is missing required code string: " +
            input.stringify(),
          )
      }
      let language = match input {
        { "language": String(value), .. } => value
        _ => "python"
      }
      Some(@types.ResponseContentPart::CodeExecution(language~, code~))
    }
    "bash_code_execution" => {
      let command = match input {
        { "command": String(value), .. } => value
        _ =>
          abort(
            "Anthropic bash_code_execution tool input is missing required command string: " +
            input.stringify(),
          )
      }
      Some(
        @types.ResponseContentPart::CodeExecution(language="bash", code=command),
      )
    }
    "text_editor_code_execution" => None
    _ => None
  }
}

///|
fn build_code_execution_result_part(
  content_obj : Json,
) -> @types.ResponseContentPart {
  normalize_code_execution_result(content_obj).to_response_content_part()
}

///|
fn upsert_tool_trace(
  tool_traces : Array[@types.ToolCallTrace],
  id : String,
  name : String,
  kind : @types.ToolCallKind,
  status : @types.ToolCallStatus,
  arguments : Json,
) -> Unit {
  // web_search/web_fetch result blocks do not carry the original request args,
  // so `{}` is used as an explicit "arguments unavailable" sentinel and never
  // overwrites a previously observed non-empty argument object.
  let effective_arguments = match arguments {
    Object(fields) if fields.is_empty() => None
    _ => Some(arguments)
  }
  for i in 0..<tool_traces.length() {
    if tool_traces[i].id == id {
      let statuses = tool_traces[i].statuses
      if statuses.length() == 0 || statuses[statuses.length() - 1] != status {
        statuses.push(status)
      }
      let next_arguments = match effective_arguments {
        Some(value) => value
        None => tool_traces[i].arguments
      }
      tool_traces[i] = @types.ToolCallTrace::new(
        id~,
        name~,
        kind~,
        statuses~,
        arguments=next_arguments,
      )
      return
    }
  }
  let next_arguments = match effective_arguments {
    Some(value) => value
    None => Json::object({})
  }
  tool_traces.push(
    @types.ToolCallTrace::new(
      id~,
      name~,
      kind~,
      statuses=[status],
      arguments=next_arguments,
    ),
  )
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
  response_format? : @types.ResponseFormat? = None,
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
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs),
  }
  let params : @types.GenerationParams = {
    ..@types.GenerationParams::empty(),
    max_tokens: Json::number(effective_max_tokens.to_double()),
    temperature: match temperature {
      Some(temp) => Json::number(temp)
      None => Json::null()
    },
    response_format,
  }
  params.apply_to_anthropic(body, {
    max_tokens: effective_max_tokens,
    max_tokens_field: "max_tokens",
  })
  if system_msg.length() > 0 {
    body["system"] = Json::string(system_msg)
  }
  if tools.length() > 0 {
    body["tools"] = Json::array(tools_to_json(tools))
  }
  Json::object(body)
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse Anthropic response
pub fn parse_response(response_json : Json) -> @types.ModelResponse {
  match response_json {
    { "content": content, "stop_reason": String(stop_reason), .. } => {
      let tool_calls = if stop_reason == "tool_use" {
        parse_tool_calls(content)
      } else {
        []
      }
      // Extract text response and structured content parts
      match content {
        Array(blocks) => {
          let text = StringBuilder::new()
          let content_parts : Array[@types.ResponseContentPart] = []
          let annotations : Array[@types.ResponseAnnotation] = []
          let tool_traces : Array[@types.ToolCallTrace] = []
          let mut has_non_text = false
          let mut text_offset = 0
          for block in blocks {
            match block {
              { "type": String("text"), "text": String(t), .. } => {
                append_anthropic_text_block_annotations(
                  annotations,
                  block,
                  text_offset,
                  text_offset + t.length(),
                )
                text_offset = text_offset + t.length()
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
              {
                "type": String("server_tool_use"),
                "id": String(id),
                "name": String(name),
                "input": input,
                ..
              } => {
                let trace_id = @interop_util.anthropic_to_openai_responses_call_id(
                  id,
                )
                match name {
                  "web_search" => {
                    upsert_tool_trace(
                      tool_traces,
                      trace_id,
                      name,
                      @types.ToolCallKind::WebSearch,
                      @types.ToolCallStatus::InProgress,
                      input,
                    )
                    has_non_text = true
                  }
                  "web_fetch" => {
                    upsert_tool_trace(
                      tool_traces,
                      trace_id,
                      name,
                      @types.ToolCallKind::Builtin(builtin_type=name),
                      @types.ToolCallStatus::InProgress,
                      input,
                    )
                    has_non_text = true
                  }
                  _ =>
                    match build_code_execution_input_part(name, input) {
                      Some(part) => {
                        content_parts.push(part)
                        has_non_text = true
                      }
                      None => {
                        upsert_tool_trace(
                          tool_traces,
                          trace_id,
                          name,
                          @types.ToolCallKind::Builtin(builtin_type=name),
                          @types.ToolCallStatus::InProgress,
                          input,
                        )
                        has_non_text = true
                      }
                    }
                }
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
                content_parts.push(
                  build_code_execution_result_part(content_obj),
                )
                has_non_text = true
              }
              {
                "type": String("bash_code_execution_tool_result"),
                "content": content_obj,
                ..
              }
              | {
                "type": String("text_editor_code_execution_tool_result"),
                "content": content_obj,
                ..
              } => {
                content_parts.push(
                  build_code_execution_result_part(content_obj),
                )
                has_non_text = true
              }
              {
                "type": String("web_search_tool_result"),
                "tool_use_id": String(tool_use_id),
                ..
              } => {
                upsert_tool_trace(
                  tool_traces,
                  @interop_util.anthropic_to_openai_responses_call_id(
                    tool_use_id,
                  ),
                  @types.web_search_tool_name(),
                  @types.ToolCallKind::WebSearch,
                  @types.ToolCallStatus::Completed,
                  Json::object({}),
                )
                has_non_text = true
              }
              {
                "type": String("web_fetch_tool_result"),
                "tool_use_id": String(tool_use_id),
                ..
              } => {
                upsert_tool_trace(
                  tool_traces,
                  @interop_util.anthropic_to_openai_responses_call_id(
                    tool_use_id,
                  ),
                  "web_fetch",
                  @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
                  @types.ToolCallStatus::Completed,
                  Json::object({}),
                )
                has_non_text = true
              }
              _ => ()
            }
          }
          let content_str = text.to_string()
          if tool_calls.length() > 0 {
            if content_parts.length() > 0 || tool_traces.length() > 0 {
              @types.ModelResponse::ToolCallsWithContent(
                tool_calls~,
                rich=@types.RichTextResponse::from_parts(
                  content=content_str,
                  content_parts~,
                  annotations~,
                  tool_traces~,
                ),
              )
            } else {
              @types.ModelResponse::ToolCalls(tool_calls)
            }
          } else if has_non_text ||
            annotations.length() > 0 ||
            tool_traces.length() > 0 {
            @types.ModelResponse::RichText(
              @types.RichTextResponse::from_parts(
                content=content_str,
                content_parts~,
                annotations~,
                tool_traces~,
              ),
            )
          } else {
            @types.ModelResponse::Text(content_str)
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
            if name == @types.web_search_tool_name() {
              let query = match input {
                { "query": String(q), .. } => Some(q)
                _ => None
              }
              result.push(@types.ToolCallRequest::web_search(id~, query~))
            } else {
              result.push(
                @types.ToolCallRequest::new(id~, name~, arguments=input),
              )
            }
          { "type": String("tool_use"), .. } =>
            abort(
              "Anthropic tool_use block is missing required id/name/input fields: " +
              item.stringify(),
            )
          _ => ()
        }
      }
    _ =>
      abort(
        "Anthropic tool_use content must be an array: " + content.stringify(),
      )
  }
  result
}
