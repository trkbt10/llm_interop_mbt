///|
/// OpenAI Responses API protocol

// =============================================================================
// Message Conversion
// =============================================================================

///|
/// Convert message array to Responses API input items format JSON array
pub fn messages_to_responses_input(
  messages : Array[@types.ModelMessage],
) -> Array[Json] {
  let input_items : Array[Json] = []
  for msg in messages {
    match msg {
      @types.ModelMessage::System(content) =>
        input_items.push({ "role": "system", "content": content })
      @types.ModelMessage::User(content~, ..) =>
        input_items.push({ "role": "user", "content": content })
      @types.ModelMessage::Assistant(content~, tool_calls~) =>
        match tool_calls {
          Some(calls) if calls.length() > 0 => {
            if content.length() > 0 {
              input_items.push({ "role": "assistant", "content": content })
            }
            for call in calls {
              input_items.push({
                "type": "function_call",
                "call_id": call.id,
                "name": call.name,
                "arguments": call.arguments.stringify(),
                "status": "completed",
              })
            }
          }
          _ => input_items.push({ "role": "assistant", "content": content })
        }
      @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
        input_items.push({
          "type": "function_call_output",
          "call_id": tool_call_id,
          "output": content,
        })
    }
  }
  input_items
}

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to JSON (Responses API format)
pub fn tool_to_responses_api_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "type": "function",
        "name": tool.name,
        "description": tool.description,
        "parameters": tool.parameters,
      }
    @types.ToolDefinitionKind::WebSearchPreview(
      search_context_size~,
      user_location_country~
    ) =>
      build_web_search_tool_json(
        "web_search_preview", search_context_size, user_location_country,
      )
    @types.ToolDefinitionKind::WebSearchPreview20250311(
      search_context_size~,
      user_location_country~
    ) =>
      build_web_search_tool_json(
        "web_search_preview_2025_03_11", search_context_size, user_location_country,
      )
  }
}

///|
fn build_web_search_tool_json(
  tool_type : String,
  search_context_size : String?,
  user_location_country : String?,
) -> Json {
  let tool : Map[String, Json] = { "type": Json::string(tool_type) }
  match search_context_size {
    Some(size) => tool["search_context_size"] = Json::string(size)
    None => ()
  }
  match user_location_country {
    Some(country) =>
      tool["user_location"] = { "type": "approximate", "country": country }
    None => ()
  }
  Json::object(tool)
}

///|
/// Convert tool definition array to Responses API format JSON array
pub fn tools_to_responses_api_json(
  tools : Array[@types.ToolDefinition],
) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_responses_api_json(tool))
  }
  result
}

// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build OpenAI Responses API request body
pub fn build_responses_api_body(
  model : String,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
) -> Json {
  let input = messages_to_responses_input(messages)
  if tools.length() > 0 {
    {
      "model": model,
      "input": Json::array(input),
      "tools": Json::array(tools_to_responses_api_json(tools)),
      "tool_choice": "auto",
    }
  } else {
    { "model": model, "input": Json::array(input) }
  }
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse OpenAI Responses API response
pub fn parse_responses_api_response(
  response_json : Json,
) -> @types.ModelResponse {
  match response_json {
    { "output": Array(outputs), .. } => {
      let text = StringBuilder::new()
      let annotations : Array[@types.ResponseAnnotation] = []
      let tool_traces : Array[@types.ToolCallTrace] = []
      let tool_calls : Array[@types.ToolCallRequest] = []
      for output in outputs {
        match output {
          { "type": String("message"), "content": Array(contents), .. } =>
            for content in contents {
              match content {
                { "type": String("output_text"), "text": String(t), .. } => {
                  if text.to_string().length() > 0 {
                    text.write_char('\n')
                  }
                  text.write_string(t)
                  push_annotations(
                    annotations,
                    parse_output_text_annotations(content),
                  )
                }
                _ => ()
              }
            }
          {
            "type": String("function_call"),
            "name": String(name),
            "arguments": String(args_str),
            ..
          } => {
            let id = match output {
              { "call_id": String(cid), .. } => cid
              { "id": String(fid), .. } => fid
              _ => ""
            }
            let arguments : Json = @json.parse(args_str) catch { _ => {} }
            tool_calls.push(@types.ToolCallRequest::new(id~, name~, arguments~))
          }
          { "type": String("web_search_call"), "id": String(id), .. } =>
            tool_traces.push(parse_web_search_trace(output, id))
          _ => () // reasoning, etc.
        }
      }
      if tool_calls.length() > 0 {
        @types.ModelResponse::ToolCalls(tool_calls)
      } else if annotations.length() > 0 || tool_traces.length() > 0 {
        @types.ModelResponse::RichText(
          @types.RichTextResponse::new(
            content=text.to_string(),
            annotations~,
            tool_traces~,
          ),
        )
      } else {
        @types.ModelResponse::Text(text.to_string())
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
  }
}

///|
fn parse_output_text_annotations(
  content : Json,
) -> Array[@types.ResponseAnnotation] {
  let result : Array[@types.ResponseAnnotation] = []
  match content {
    { "annotations": Array(items), .. } =>
      for item in items {
        match item {
          {
            "type": String("url_citation"),
            "url": String(url),
            "start_index": Number(start, ..),
            "end_index": Number(end_, ..),
            ..
          } => {
            let title = match item {
              { "title": String(t), .. } => Some(t)
              _ => None
            }
            result.push(
              @types.ResponseAnnotation::url_citation(
                url~,
                start_index=start.to_int(),
                end_index=end_.to_int(),
                title~,
              ),
            )
          }
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
fn parse_web_search_trace(output : Json, id : String) -> @types.ToolCallTrace {
  let arguments : Map[String, Json] = {}
  match output {
    { "action": { "query": String(query), .. }, .. } =>
      arguments["query"] = Json::string(query)
    _ => ()
  }
  match output {
    { "action": { "queries": Array(queries), .. }, .. } =>
      arguments["queries"] = Json::array(queries)
    _ => ()
  }
  let statuses = match output {
    { "status": String("in_progress"), .. } =>
      [@types.ToolCallStatus::InProgress]
    { "status": String("searching"), .. } => [@types.ToolCallStatus::Searching]
    { "status": String("completed"), .. } => [@types.ToolCallStatus::Completed]
    _ => []
  }
  @types.ToolCallTrace::new(
    id~,
    name="web_search",
    kind=@types.ToolCallKind::WebSearch,
    statuses~,
    arguments=Json::object(arguments),
  )
}
