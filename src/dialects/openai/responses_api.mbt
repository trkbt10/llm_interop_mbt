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
      @types.ModelMessage::User(content~, content_parts~, ..) =>
        match content_parts {
          Some(parts) => {
            let content_blocks : Array[Json] = []
            for part in parts {
              // Ref: https://platform.openai.com/docs/api-reference/responses/create — input content types
              match part {
                // Ref: InputText — {"type":"input_text","text":"..."}
                @types.ContentPart::Text(text) =>
                  content_blocks.push({ "type": "input_text", "text": text })
                // Ref: InputImage — {"type":"input_image","image_url":"...","detail":"..."}
                @types.ContentPart::ImageUrl(url~, detail~) => {
                  let img : Map[String, Json] = {
                    "type": Json::string("input_image"),
                    "image_url": Json::string(url),
                  }
                  match detail {
                    Some(d) => img["detail"] = Json::string(d)
                    None => ()
                  }
                  content_blocks.push(Json::object(img))
                }
                // Ref: InputImage with data URL
                @types.ContentPart::ImageBase64(data~, media_type~) =>
                  content_blocks.push({
                    "type": "input_image",
                    "image_url": "data:\{media_type};base64,\{data}",
                  })
                // Ref: InputAudio — {"type":"input_audio","data":"...","format":"..."}
                @types.ContentPart::Audio(data~, format~) =>
                  content_blocks.push({
                    "type": "input_audio",
                    "data": data,
                    "format": format,
                  })
                // Ref: InputFile — {"type":"input_file","file_data":"data:...;base64,...","filename":"..."}
                @types.ContentPart::Document(data~, media_type~, title~) => {
                  let doc : Map[String, Json] = {
                    "type": Json::string("input_file"),
                    "file_data": Json::string(
                      "data:\{media_type};base64,\{data}",
                    ),
                  }
                  match title {
                    Some(t) => doc["filename"] = Json::string(t)
                    None => ()
                  }
                  content_blocks.push(Json::object(doc))
                }
                // Ref: InputFile — {"type":"input_file","file_id":"..."}
                @types.ContentPart::FileRef(file_id~, ..) =>
                  content_blocks.push({
                    "type": "input_file",
                    "file_id": file_id,
                  })
                // Responses API has no native video input; use input_file with data URL
                @types.ContentPart::Video(data~, media_type~) =>
                  content_blocks.push({
                    "type": "input_file",
                    "file_data": "data:\{media_type};base64,\{data}",
                  })
              }
            }
            input_items.push({
              "role": "user",
              "content": Json::array(content_blocks),
            })
          }
          None => input_items.push({ "role": "user", "content": content })
        }
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
// Responses API Output Builders (used by cross-dialect to_responses transforms)
// =============================================================================

///|
/// Build a Responses API function_call output item.
pub fn build_responses_function_call(
  call_id : String,
  name : String,
  arguments : Json,
) -> Json {
  {
    "type": "function_call",
    "id": call_id,
    "call_id": call_id,
    "name": name,
    "arguments": arguments.stringify(),
    "status": "completed",
  }
}

///|
/// Build a Responses API web_search_call output item.
pub fn build_responses_web_search_call(call_id : String, input : Json) -> Json {
  {
    "type": "web_search_call",
    "id": call_id,
    "status": "completed",
    "action": @types.build_web_search_action(input),
  }
}

///|
/// Build a Responses API message output wrapping content parts.
pub fn build_responses_message_output(content_parts : Array[Json]) -> Json {
  {
    "type": "message",
    "role": "assistant",
    "content": Json::array(content_parts),
  }
}

///|
/// Build a Responses API reasoning output item.
/// Ref: ResponseReasoningItem — {"type":"reasoning","summary":[{"type":"summary_text","text":"..."}]}
pub fn build_responses_reasoning_item(text : String) -> Json {
  {
    "type": "reasoning",
    "summary": Json::array([{ "type": "summary_text", "text": text }]),
  }
}

///|
/// Assemble Responses API output array.
///
/// Responses API output ordering (Ref: ResponseOutputItem):
///   1. reasoning items (ResponseReasoningItem)
///   2. tool call items (function_call, web_search_call)
///   3. message item (ResponseOutputMessage with content: [output_text, refusal, output_image])
///
/// Parameters:
///   - text_parts: message content blocks (output_text, refusal, output_image JSON)
///   - tool_outputs: function_call and web_search_call items
///   - reasoning_outputs: reasoning items (optional, default [])
pub fn assemble_responses_output(
  text_parts : Array[Json],
  tool_outputs : Array[Json],
  reasoning_outputs? : Array[Json] = [],
) -> Array[Json] {
  let result : Array[Json] = []
  // 1. Reasoning items first
  for r in reasoning_outputs {
    result.push(r)
  }
  // 2. Tool calls
  for o in tool_outputs {
    result.push(o)
  }
  // 3. Message item (text, refusal, images)
  if text_parts.length() > 0 {
    result.push(build_responses_message_output(text_parts))
  }
  result
}

///|
/// Convert ModelResponse to Responses API output array.
pub fn model_response_to_responses_output(
  response : @types.ModelResponse,
) -> Array[Json] {
  match response {
    @types.ModelResponse::Text(content) =>
      build_responses_output_from_rich_content(
        [@types.ResponseContentPart::OutputText(content)],
        [],
        [],
      )
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          build_responses_output_from_rich_content(
            parts,
            rich.annotations,
            rich.tool_traces,
          )
        None =>
          build_responses_output_from_rich_content(
            [@types.ResponseContentPart::OutputText(rich.content)],
            rich.annotations,
            rich.tool_traces,
          )
      }
    @types.ModelResponse::ToolCalls(calls) =>
      build_responses_output_from_tool_calls(calls)
    @types.ModelResponse::ModelError(_) => []
    @types.ModelResponse::RateLimited(_) => []
  }
}

///|
/// Convert ModelResponse to full Responses API response JSON.
pub fn model_response_to_responses_json(
  response : @types.ModelResponse,
  response_id~ : String,
  model~ : String,
) -> Json {
  match response {
    @types.ModelResponse::ModelError(msg) =>
      { "error": { "type": "error", "message": msg } }
    @types.ModelResponse::RateLimited(retry_after~) =>
      {
        "error": {
          "type": "rate_limit_error",
          "message": "Rate limited",
          "retry_after": retry_after,
        },
      }
    _ =>
      {
        "id": response_id,
        "object": "response",
        "status": "completed",
        "output": Json::array(model_response_to_responses_output(response)),
        "model": model,
      }
  }
}

///|
fn build_responses_output_from_tool_calls(
  calls : Array[@types.ToolCallRequest],
) -> Array[Json] {
  let output : Array[Json] = []
  for call in calls {
    match call.kind {
      @types.ToolCallKind::Function =>
        output.push(
          build_responses_function_call(call.id, call.name, call.arguments),
        )
      @types.ToolCallKind::WebSearch =>
        output.push(build_responses_web_search_call(call.id, call.arguments))
    }
  }
  output
}

///|
fn build_responses_output_from_rich_content(
  parts : Array[@types.ResponseContentPart],
  annotations : Array[@types.ResponseAnnotation],
  tool_traces : Array[@types.ToolCallTrace],
) -> Array[Json] {
  let message_parts : Array[Json] = []
  let reasoning_outputs : Array[Json] = []
  let tool_outputs : Array[Json] = []
  for trace in tool_traces {
    if trace.kind == @types.ToolCallKind::WebSearch {
      tool_outputs.push({
        "type": "web_search_call",
        "id": trace.id,
        "status": tool_trace_status_to_json(trace.statuses),
        "action": @types.build_web_search_action(trace.arguments),
      })
    }
  }
  let text_offsets : Array[(Int, Int)] = []
  let mut offset = 0
  for part in parts {
    match part {
      @types.ResponseContentPart::OutputText(text) => {
        text_offsets.push((offset, offset + text.length()))
        offset = offset + text.length()
      }
      _ => ()
    }
  }
  let mut text_index = 0
  for part in parts {
    match part {
      @types.ResponseContentPart::OutputText(text) => {
        let (seg_start, seg_end) = text_offsets[text_index]
        let segment_annotations : Array[Json] = []
        for annotation in annotations {
          match annotation {
            @types.ResponseAnnotation::UrlCitation(start_index~, end_index~, ..) =>
              if start_index >= seg_start && end_index <= seg_end {
                segment_annotations.push(
                  response_annotation_to_json(annotation),
                )
              }
          }
        }
        message_parts.push({
          "type": "output_text",
          "text": text,
          "annotations": Json::array(segment_annotations),
        })
        text_index = text_index + 1
      }
      @types.ResponseContentPart::OutputImage(url~) =>
        message_parts.push({ "type": "output_image", "image_url": url })
      @types.ResponseContentPart::Refusal(reason) =>
        message_parts.push({ "type": "refusal", "refusal": reason })
      @types.ResponseContentPart::Thinking(text~) =>
        reasoning_outputs.push(build_responses_reasoning_item(text))
      @types.ResponseContentPart::RedactedThinking(..) => ()
      @types.ResponseContentPart::CodeExecution(language~, code~) =>
        message_parts.push({
          "type": "output_text",
          "text": "```\{language}\n\{code}\n```",
        })
      @types.ResponseContentPart::CodeResult(outcome~, output~) =>
        message_parts.push({
          "type": "output_text",
          "text": "Execution [\{outcome}]: \{output}",
        })
      @types.ResponseContentPart::AudioOutput(transcript~, ..) =>
        message_parts.push({ "type": "output_text", "text": transcript })
    }
  }
  assemble_responses_output(message_parts, tool_outputs, reasoning_outputs~)
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
    { "output": Array(outputs), .. } => parse_responses_output(outputs)
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
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
      { "type": String("reasoning"), .. } =>
        if append_response_reasoning_item(output, content_parts) {
          has_non_text = true
        }
      _ => ()
    }
  }
  let text = concatenate_output_text_parts(content_parts)
  let content_parts_opt : Array[@types.ResponseContentPart]? = if has_non_text {
    Some(content_parts)
  } else {
    None
  }
  if tool_calls.length() > 0 {
    @types.ModelResponse::ToolCalls(tool_calls)
  } else if has_non_text || annotations.length() > 0 || tool_traces.length() > 0 {
    @types.ModelResponse::RichText(
      @types.RichTextResponse::new(
        content=text,
        content_parts=content_parts_opt,
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
      _ => ()
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
          _ => ()
        }
      }
    _ => ()
  }
  if found {
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
          _ => ()
        }
      }
    _ => ()
  }
  added_summary
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

///|
fn response_annotation_to_json(annotation : @types.ResponseAnnotation) -> Json {
  match annotation {
    @types.ResponseAnnotation::UrlCitation(
      title~,
      url~,
      start_index~,
      end_index~
    ) => {
      let result : Map[String, Json] = {
        "type": Json::string("url_citation"),
        "url": Json::string(url),
        "start_index": Json::number(start_index.to_double()),
        "end_index": Json::number(end_index.to_double()),
      }
      match title {
        Some(value) => result["title"] = Json::string(value)
        None => ()
      }
      Json::object(result)
    }
  }
}

///|
fn tool_trace_status_to_json(statuses : Array[@types.ToolCallStatus]) -> Json {
  if statuses.length() == 0 {
    return Json::string("completed")
  }
  match statuses[statuses.length() - 1] {
    @types.ToolCallStatus::InProgress => Json::string("in_progress")
    @types.ToolCallStatus::Searching => Json::string("searching")
    @types.ToolCallStatus::Completed => Json::string("completed")
  }
}
