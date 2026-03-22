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
///   2. message item (ResponseOutputMessage with content: [output_text, refusal, output_image])
///   3. tool call items (function_call, web_search_call)
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
  // 2. Message item (text, refusal, images)
  if text_parts.length() > 0 {
    result.push(build_responses_message_output(text_parts))
  }
  // 3. Tool calls
  for o in tool_outputs {
    result.push(o)
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
      let content_parts : Array[@types.ResponseContentPart] = []
      let annotations : Array[@types.ResponseAnnotation] = []
      let tool_traces : Array[@types.ToolCallTrace] = []
      let tool_calls : Array[@types.ToolCallRequest] = []
      let mut has_non_text = false
      // Ref: ResponseOutputItem variants — https://platform.openai.com/docs/api-reference/responses
      for output in outputs {
        match output {
          // Ref: ResponseOutputMessage — {"type":"message","role":"assistant","content":[...]}
          { "type": String("message"), "content": Array(contents), .. } =>
            for content in contents {
              match content {
                // Ref: ResponseOutputText — {"type":"output_text","text":"...","annotations":[...]}
                { "type": String("output_text"), "text": String(t), .. } => {
                  if text.to_string().length() > 0 {
                    text.write_char('\n')
                  }
                  text.write_string(t)
                  content_parts.push(@types.ResponseContentPart::OutputText(t))
                  push_annotations(
                    annotations,
                    parse_output_text_annotations(content),
                  )
                }
                // Ref: ResponseOutputImage — {"type":"output_image","image_url":"..."}
                { "type": String("output_image"), "image_url": String(url), .. } => {
                  content_parts.push(
                    @types.ResponseContentPart::OutputImage(url~),
                  )
                  has_non_text = true
                }
                // Ref: ResponseOutputRefusal — {"type":"refusal","refusal":"..."}
                { "type": String("refusal"), "refusal": String(reason), .. } => {
                  content_parts.push(
                    @types.ResponseContentPart::Refusal(reason),
                  )
                  has_non_text = true
                }
                _ => ()
              }
            }
          // Ref: ResponseFunctionToolCall — {"type":"function_call","name":"...","arguments":"...","call_id":"..."}
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
          // Ref: ResponseFunctionWebSearch — {"type":"web_search_call","id":"...","action":{...}}
          { "type": String("web_search_call"), "id": String(id), .. } =>
            tool_traces.push(parse_web_search_trace(output, id))
          // Ref: ResponseReasoningItem — {"type":"reasoning","summary":[{"type":"summary_text","text":"..."}],"content":[{"type":"reasoning_text","text":"..."}]}
          // content array has {"type":"reasoning_text","text":"..."} blocks (detailed reasoning)
          // summary array has {"type":"summary_text","text":"..."} blocks (condensed)
          // We read content first (full detail), fallback to summary
          { "type": String("reasoning"), .. } => {
            let mut found = false
            // Try content array first (full reasoning text)
            match output {
              { "content": Array(content_blocks), .. } =>
                for rblock in content_blocks {
                  match rblock {
                    { "type": String("reasoning_text"), "text": String(t), .. }
                    | { "type": String("text"), "text": String(t), .. } => {
                      content_parts.push(
                        @types.ResponseContentPart::Thinking(text=t),
                      )
                      has_non_text = true
                      found = true
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
            // Fallback to summary array
            if not(found) {
              match output {
                { "summary": Array(summary_blocks), .. } =>
                  for sblock in summary_blocks {
                    match sblock {
                      { "type": String("summary_text"), "text": String(t), .. } => {
                        content_parts.push(
                          @types.ResponseContentPart::Thinking(text=t),
                        )
                        has_non_text = true
                      }
                      _ => ()
                    }
                  }
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
      let parts_opt : Array[@types.ResponseContentPart]? = if has_non_text {
        Some(content_parts)
      } else {
        None
      }
      if tool_calls.length() > 0 {
        @types.ModelResponse::ToolCalls(tool_calls)
      } else if has_non_text ||
        annotations.length() > 0 ||
        tool_traces.length() > 0 {
        @types.ModelResponse::RichText(
          @types.RichTextResponse::new(
            content=text.to_string(),
            content_parts=parts_opt,
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
    name=@types.web_search_tool_name(),
    kind=@types.ToolCallKind::WebSearch,
    statuses~,
    arguments=Json::object(arguments),
  )
}
