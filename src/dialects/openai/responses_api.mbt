///|
/// OpenAI Responses API protocol

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to JSON (Responses API format)
fn tool_to_responses_api_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "type": "function",
        "name": tool.name,
        "description": tool.description,
        "parameters": tool.parameters,
      }
    @types.ToolDefinitionKind::Builtin(builtin_type~, config~) =>
      build_builtin_tool_json(builtin_type, config)
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
fn build_builtin_tool_json(type_ : String, config : Json) -> Json {
  let result : Map[String, Json] = { "type": Json::string(type_) }
  match config {
    Object(fields) =>
      for key, value in fields {
        result[key] = value
      }
    _ => ()
  }
  Json::object(result)
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
fn tools_to_responses_api_json(
  tools : Array[@types.ToolDefinition],
) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_responses_api_json(tool))
  }
  result
}

///|
fn is_actionable_builtin_responses_tool_item_type(type_ : String) -> Bool {
  [
    "computer_call", "local_shell_call", "shell_call", "apply_patch_call", "mcp_call",
    "mcp_approval_request",
  ].contains(type_)
}

///|
// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build OpenAI Responses API request body
pub fn build_responses_api_body(
  model : String,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  response_format? : @types.ResponseFormat? = None,
) -> Json {
  let input = @openai_responses_contract.messages_to_responses_input(messages)
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "input": Json::array(input),
  }
  let params : @types.GenerationParams = {
    ..@types.GenerationParams::empty(),
    response_format,
  }
  params.apply_to_responses(body)
  if tools.length() > 0 {
    body["tools"] = Json::array(tools_to_responses_api_json(tools))
    body["tool_choice"] = Json::string("auto")
  }
  Json::object(body)
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
    { "output": Array(outputs), .. } => parse_responses_output(outputs)
    { "error": error_obj, .. } => parse_responses_api_error(error_obj)
    _ =>
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="Unknown response format",
          payload=Some(response_json),
        ),
      )
  }
}

///|
fn parse_responses_api_error(error_obj : Json) -> @types.ModelResponse {
  match error_obj {
    { "message": String(message), .. } => {
      let failure_type = match error_obj {
        { "type": String(type_), .. } => type_
        _ => "error"
      }
      let failure_code = match error_obj {
        { "code": Number(code, ..), .. } => Some(code.to_int())
        _ => None
      }
      let retry_after = match error_obj {
        { "retry_after": Number(retry_after, ..), .. } =>
          Some(retry_after.to_int())
        _ => None
      }
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::new(
          type_=failure_type,
          message~,
          code=failure_code,
          retry_after~,
          payload=Some(error_obj),
        ),
      )
    }
    _ =>
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::new(
          type_="error",
          message=error_obj.stringify(),
          payload=Some(error_obj),
        ),
      )
  }
}

///|
fn parse_responses_output(outputs : Array[Json]) -> @types.ModelResponse {
  let content_parts : Array[@types.ResponseContentPart] = []
  let annotations : Array[@types.ResponseAnnotation] = []
  let tool_traces : Array[@types.ToolCallTrace] = []
  let tool_calls : Array[@types.ToolCallRequest] = []
  let mut has_non_text = false
  for output in outputs {
    match output {
      { "type": String("message"), "content": Array(contents), .. } => {
        let (_, message_has_non_text) = append_response_message_contents(
          contents, content_parts, annotations,
        )
        if message_has_non_text {
          has_non_text = true
        }
      }
      {
        "type": String("function_call"),
        "name": String(name),
        "arguments": String(args_str),
        ..
      } => {
        let id = extract_responses_tool_item_id(output)
        let arguments = parse_responses_tool_call_arguments_or_abort(
          args_str, output,
        )
        tool_calls.push(@types.ToolCallRequest::new(id~, name~, arguments~))
      }
      { "type": String("web_search_call"), "id": String(id), .. } =>
        tool_traces.push(parse_web_search_trace(output, id))
      { "type": String("reasoning"), .. } =>
        if append_response_reasoning_item(output, content_parts) {
          has_non_text = true
        }
      { "type": String(type_), .. } =>
        if @openai_responses_contract.is_builtin_responses_tool_item_type(type_) {
          if is_actionable_builtin_responses_tool_item_type(type_) {
            tool_calls.push(parse_builtin_tool_call(output, type_))
          } else {
            tool_traces.push(parse_builtin_trace(output, type_))
          }
        } else {
          abort("Unsupported Responses output item type: " + output.stringify())
        }
      _ =>
        abort(
          "Responses output item must be an object with a supported type: " +
          output.stringify(),
        )
    }
  }
  let text = concatenate_output_text_parts(content_parts)
  if tool_calls.length() > 0 {
    if content_parts.length() > 0 ||
      annotations.length() > 0 ||
      tool_traces.length() > 0 {
      @types.ModelResponse::ToolCallsWithContent(
        tool_calls~,
        rich=@types.RichTextResponse::from_parts(
          content=text,
          content_parts~,
          annotations~,
          tool_traces~,
        ),
      )
    } else {
      @types.ModelResponse::ToolCalls(tool_calls)
    }
  } else if has_non_text || annotations.length() > 0 || tool_traces.length() > 0 {
    @types.ModelResponse::RichText(
      @types.RichTextResponse::from_parts(
        content=text,
        content_parts~,
        annotations~,
        tool_traces~,
      ),
    )
  } else {
    @types.ModelResponse::Text(text)
  }
}

///|
fn append_response_message_contents(
  contents : Array[Json],
  content_parts : Array[@types.ResponseContentPart],
  annotations : Array[@types.ResponseAnnotation],
) -> (Bool, Bool) {
  let mut saw_output_text = false
  let mut has_non_text = false
  for content in contents {
    match content {
      { "type": String("output_text"), "text": String(text), .. } => {
        saw_output_text = true
        content_parts.push(@types.ResponseContentPart::OutputText(text))
        push_annotations_unique(
          annotations,
          parse_output_text_annotations(content),
        )
      }
      { "type": String("output_image"), "image_url": String(url), .. } => {
        content_parts.push(@types.ResponseContentPart::OutputImage(url~))
        has_non_text = true
      }
      { "type": String("refusal"), "refusal": String(reason), .. } => {
        content_parts.push(@types.ResponseContentPart::Refusal(reason))
        has_non_text = true
      }
      { "type": String(_), .. } =>
        abort(
          "Unsupported Responses message content type: " + content.stringify(),
        )
      _ =>
        abort(
          "Responses message content must be an object with a supported type: " +
          content.stringify(),
        )
    }
  }
  (saw_output_text, has_non_text)
}

///|
fn append_response_reasoning_item(
  output : Json,
  content_parts : Array[@types.ResponseContentPart],
) -> Bool {
  let mut found = false
  match output {
    { "content": Array(content_blocks), .. } =>
      for block in content_blocks {
        match block {
          { "type": String("reasoning_text"), "text": String(text), .. }
          | { "type": String("text"), "text": String(text), .. } => {
            content_parts.push(@types.ResponseContentPart::Thinking(text~))
            found = true
          }
          { "type": String(_), .. } =>
            abort(
              "Unsupported Responses reasoning content block: " +
              block.stringify(),
            )
          _ =>
            abort(
              "Responses reasoning content block must be an object with a supported type: " +
              block.stringify(),
            )
        }
      }
    _ => ()
  }
  if found {
    match output {
      { "encrypted_content": String(data), .. } =>
        content_parts.push(@types.ResponseContentPart::RedactedThinking(data~))
      _ => ()
    }
    return true
  }
  let mut added_summary = false
  match output {
    { "summary": Array(summary_blocks), .. } =>
      for block in summary_blocks {
        match block {
          { "type": String("summary_text"), "text": String(text), .. } => {
            content_parts.push(@types.ResponseContentPart::Thinking(text~))
            added_summary = true
          }
          { "type": String(_), .. } =>
            abort(
              "Unsupported Responses reasoning summary block: " +
              block.stringify(),
            )
          _ =>
            abort(
              "Responses reasoning summary block must be an object with a supported type: " +
              block.stringify(),
            )
        }
      }
    _ => ()
  }
  match output {
    { "encrypted_content": String(data), .. } => {
      content_parts.push(@types.ResponseContentPart::RedactedThinking(data~))
      true
    }
    _ => added_summary
  }
}

///|
fn concatenate_output_text_parts(
  content_parts : Array[@types.ResponseContentPart],
) -> String {
  let text = StringBuilder::new()
  for part in content_parts {
    match part {
      @types.ResponseContentPart::OutputText(value) => text.write_string(value)
      _ => ()
    }
  }
  text.to_string()
}

///|
fn parse_output_text_annotations(
  content : Json,
) -> Array[@types.ResponseAnnotation] {
  let result : Array[@types.ResponseAnnotation] = []
  match content {
    { "annotations": Array(items), .. } =>
      push_annotations_unique(result, parse_response_annotations(items))
    _ => ()
  }
  result
}

///|
fn parse_response_annotation_json(
  annotation : Json,
) -> Array[@types.ResponseAnnotation] {
  match annotation {
    Array(items) => parse_response_annotations(items)
    _ => parse_response_annotations([annotation])
  }
}

///|
fn parse_response_annotations(
  items : Array[Json],
) -> Array[@types.ResponseAnnotation] {
  let result : Array[@types.ResponseAnnotation] = []
  for item in items {
    result.push(@types.parse_interop_response_annotation(item))
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
    name=@types.web_search_tool_name(),
    kind=@types.ToolCallKind::WebSearch,
    statuses~,
    arguments=Json::object(arguments),
  )
}

///|
fn parse_builtin_trace(output : Json, type_ : String) -> @types.ToolCallTrace {
  let id = extract_responses_tool_item_id(output)
  let name = match output {
    { "name": String(value), .. } => value
    _ => type_
  }
  @types.ToolCallTrace::new(
    id~,
    name~,
    kind=@types.ToolCallKind::Builtin(builtin_type=type_),
    statuses=parse_responses_tool_statuses(output),
    arguments=output,
  )
}

///|
fn parse_builtin_tool_call(
  output : Json,
  type_ : String,
) -> @types.ToolCallRequest {
  let id = extract_responses_tool_item_id(output)
  let name = match output {
    { "name": String(value), .. } => value
    _ => type_
  }
  @types.ToolCallRequest::builtin(id~, type_~, payload=output, name~)
}

///|
fn extract_responses_tool_item_id(item : Json) -> String {
  match item {
    { "call_id": String(value), .. } => value
    { "approval_request_id": String(value), .. } => value
    { "id": String(value), .. } => value
    _ =>
      abort(
        "Responses tool item is missing a required id field: " +
        item.stringify(),
      )
  }
}

///|
fn parse_responses_tool_call_arguments_or_abort(
  args_str : String,
  item : Json,
) -> Json {
  @json.parse(args_str) catch {
    _ =>
      abort(
        "Responses function_call arguments must be valid JSON: " +
        item.stringify(),
      )
  }
}

///|
fn parse_responses_tool_statuses(item : Json) -> Array[@types.ToolCallStatus] {
  match item {
    { "status": String("searching"), .. } => [@types.ToolCallStatus::Searching]
    { "status": String("completed"), .. } => [@types.ToolCallStatus::Completed]
    { "status": String("in_progress"), .. }
    | { "status": String("calling"), .. }
    | { "status": String("generating"), .. }
    | { "status": String("interpreting"), .. } =>
      [@types.ToolCallStatus::InProgress]
    _ => []
  }
}

///|
fn push_annotations_unique(
  target : Array[@types.ResponseAnnotation],
  incoming : Array[@types.ResponseAnnotation],
) -> Unit {
  for annotation in incoming {
    if not(target.contains(annotation)) {
      target.push(annotation)
    }
  }
}
