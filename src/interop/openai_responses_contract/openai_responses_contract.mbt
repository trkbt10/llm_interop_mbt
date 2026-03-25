///|
/// OpenAI Responses contract helpers shared by cross-dialect transforms.

///|
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
              match part {
                @types.ContentPart::Text(text) =>
                  content_blocks.push({ "type": "input_text", "text": text })
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
                @types.ContentPart::ImageBase64(data~, media_type~) =>
                  content_blocks.push({
                    "type": "input_image",
                    "image_url": "data:\{media_type};base64,\{data}",
                  })
                @types.ContentPart::Audio(data~, format~) =>
                  content_blocks.push({
                    "type": "input_audio",
                    "data": data,
                    "format": format,
                  })
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
                @types.ContentPart::FileRef(file_id~, ..) =>
                  content_blocks.push({
                    "type": "input_file",
                    "file_id": file_id,
                  })
                @types.ContentPart::FileUrl(url~) =>
                  content_blocks.push({ "type": "input_file", "file_url": url })
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
              match call.kind {
                @types.ToolCallKind::Function =>
                  input_items.push({
                    "type": "function_call",
                    "call_id": responses_tool_call_id(call.id),
                    "name": call.name,
                    "arguments": call.arguments.stringify(),
                    "status": "completed",
                  })
                @types.ToolCallKind::WebSearch =>
                  input_items.push(
                    build_responses_web_search_call(call.id, call.arguments),
                  )
                @types.ToolCallKind::Builtin(builtin_type~) =>
                  input_items.push(
                    build_responses_builtin_tool_item(
                      builtin_type,
                      call.id,
                      call.name,
                      call.arguments,
                    ),
                  )
              }
            }
          }
          _ => input_items.push({ "role": "assistant", "content": content })
        }
      @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
        match parse_embedded_responses_tool_result_item(tool_call_id, content) {
          Some(item) => input_items.push(item)
          None =>
            match embedded_responses_tool_result_type(content) {
              Some(type_) =>
                abort(
                  "Unsupported embedded Responses tool result item type: \{type_}",
                )
              None =>
                input_items.push({
                  "type": "function_call_output",
                  "call_id": responses_tool_call_id(tool_call_id),
                  "output": content,
                })
            }
        }
    }
  }
  input_items
}

///|
pub fn model_response_to_responses_output(
  response : @types.ModelResponse,
) -> Array[Json] {
  match response.as_failure() {
    Some(_) => return []
    None => ()
  }
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
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      build_responses_output_from_mixed_tool_calls(tool_calls, rich)
    _ => []
  }
}

///|
pub fn model_response_to_responses_json(
  response : @types.ModelResponse,
  response_id~ : String,
  model~ : String,
) -> Json {
  match response.as_failure() {
    Some(failure) => failure_to_responses_error_json(failure)
    None =>
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
fn failure_to_responses_error_json(failure : @types.ModelFailure) -> Json {
  let error : Map[String, Json] = {}
  error["type"] = Json::string(failure.type_)
  error["message"] = Json::string(failure.message)
  match failure.code {
    Some(code) => error["code"] = Json::number(code.to_double())
    None => ()
  }
  match failure.retry_after {
    Some(retry_after) =>
      error["retry_after"] = Json::number(retry_after.to_double())
    None => ()
  }
  match failure.payload {
    Some(payload) => error["payload"] = payload
    None => ()
  }
  match failure.body {
    Some(body) => error["body"] = Json::string(body)
    None => ()
  }
  { "error": Json::object(error) }
}

///|
pub fn is_builtin_responses_tool_item_type(type_ : String) -> Bool {
  [
    "file_search_call", "computer_call", "computer_call_output", "tool_search_output",
    "image_generation_call", "code_interpreter_call", "local_shell_call", "local_shell_call_output",
    "shell_call", "shell_call_output", "apply_patch_call", "apply_patch_call_output",
    "mcp_list_tools", "mcp_approval_request", "mcp_approval_response", "mcp_call",
  ].contains(type_)
}

///|
fn parse_embedded_responses_tool_result_item(
  tool_call_id : String,
  content : String,
) -> Json? {
  let parsed : Json = @json.parse(content) catch { _ => return None }
  match parsed {
    { "type": String(type_), .. } =>
      if is_raw_responses_tool_result_item_type(type_) {
        Some(ensure_tool_result_item_id(parsed, type_, tool_call_id))
      } else {
        None
      }
    _ => None
  }
}

///|
fn embedded_responses_tool_result_type(content : String) -> String? {
  let parsed : Json = @json.parse(content) catch { _ => return None }
  match parsed {
    { "type": String(type_), .. } => Some(type_)
    _ => None
  }
}

///|
fn is_raw_responses_tool_result_item_type(type_ : String) -> Bool {
  [
    "function_call_output", "custom_tool_call_output", "computer_call_output", "local_shell_call_output",
    "shell_call_output", "apply_patch_call_output", "mcp_approval_response",
  ].contains(type_)
}

///|
fn ensure_tool_result_item_id(
  item : Json,
  type_ : String,
  tool_call_id : String,
) -> Json {
  match item {
    Object(fields) => {
      let result : Map[String, Json] = fields
      match type_ {
        "mcp_approval_response" =>
          if !result.contains("approval_request_id") &&
            tool_call_id.length() > 0 {
            result["approval_request_id"] = Json::string(tool_call_id)
          }
        "computer_call_output" | "local_shell_call_output" =>
          if !result.contains("id") && tool_call_id.length() > 0 {
            result["id"] = Json::string(tool_call_id)
          }
        "function_call_output" | "custom_tool_call_output" =>
          if !result.contains("call_id") && tool_call_id.length() > 0 {
            result["call_id"] = Json::string(
              responses_tool_call_id(tool_call_id),
            )
          }
        _ =>
          if !result.contains("call_id") && tool_call_id.length() > 0 {
            result["call_id"] = Json::string(tool_call_id)
          }
      }
      Json::object(result)
    }
    _ => item
  }
}

///|
fn build_responses_function_call(
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
fn build_responses_web_search_call(call_id : String, input : Json) -> Json {
  {
    "type": "web_search_call",
    "id": call_id,
    "status": "completed",
    "action": @types.build_web_search_action(input),
  }
}

///|
fn build_responses_builtin_tool_item(
  type_ : String,
  id : String,
  name : String,
  payload : Json,
  statuses? : Array[@types.ToolCallStatus] = [],
) -> Json {
  let result : Map[String, Json] = { "type": Json::string(type_) }
  match payload {
    Object(fields) =>
      for key, value in fields {
        if key != "type" {
          result[key] = value
        }
      }
    _ => ()
  }
  if !result.contains("id") &&
    !result.contains("call_id") &&
    !result.contains("approval_request_id") &&
    id.length() > 0 {
    result["id"] = Json::string(id)
  }
  if !result.contains("name") && name.length() > 0 {
    result["name"] = Json::string(name)
  }
  if !result.contains("status") && statuses.length() > 0 {
    result["status"] = tool_trace_status_to_json(statuses)
  }
  Json::object(result)
}

///|
fn responses_tool_call_id(id : String) -> String {
  @interop_util.convert_tool_call_id_to(
    id,
    @interop_util.ToolCallIdProvider::OpenAIResponsesApi,
  )
}

///|
fn build_responses_message_output(content_parts : Array[Json]) -> Json {
  {
    "type": "message",
    "role": "assistant",
    "content": Json::array(content_parts),
  }
}

///|
fn build_responses_reasoning_item(
  text : String,
  encrypted_content? : String? = None,
) -> Json {
  let item : Map[String, Json] = { "type": Json::string("reasoning") }
  if text.length() > 0 {
    item["summary"] = Json::array([{ "type": "summary_text", "text": text }])
  } else {
    item["summary"] = Json::array([])
  }
  match encrypted_content {
    Some(value) => item["encrypted_content"] = Json::string(value)
    None => ()
  }
  Json::object(item)
}

///|
fn assemble_responses_output(
  text_parts : Array[Json],
  tool_outputs : Array[Json],
  reasoning_outputs? : Array[Json] = [],
) -> Array[Json] {
  let result : Array[Json] = []
  for r in reasoning_outputs {
    result.push(r)
  }
  for o in tool_outputs {
    result.push(o)
  }
  if text_parts.length() > 0 {
    result.push(build_responses_message_output(text_parts))
  }
  result
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
          build_responses_function_call(
            responses_tool_call_id(call.id),
            call.name,
            call.arguments,
          ),
        )
      @types.ToolCallKind::WebSearch =>
        output.push(build_responses_web_search_call(call.id, call.arguments))
      @types.ToolCallKind::Builtin(builtin_type~) =>
        if builtin_type == @types.web_search_tool_name() {
          output.push(build_responses_web_search_call(call.id, call.arguments))
        } else {
          output.push(
            build_responses_builtin_tool_item(
              builtin_type,
              call.id,
              call.name,
              call.arguments,
            ),
          )
        }
    }
  }
  output
}

///|
fn rich_parts_for_responses_output(
  rich : @types.RichTextResponse,
) -> Array[@types.ResponseContentPart] {
  match rich.content_parts {
    Some(parts) => parts
    None =>
      if rich.content.length() > 0 {
        [@types.ResponseContentPart::OutputText(rich.content)]
      } else {
        []
      }
  }
}

///|
fn build_responses_output_from_mixed_tool_calls(
  tool_calls : Array[@types.ToolCallRequest],
  rich : @types.RichTextResponse,
) -> Array[Json] {
  let (message_parts, trace_tool_outputs, reasoning_outputs) = decompose_responses_rich_content(
    rich_parts_for_responses_output(rich),
    rich.annotations,
    rich.tool_traces,
  )
  let tool_outputs = trace_tool_outputs
  for output in build_responses_output_from_tool_calls(tool_calls) {
    tool_outputs.push(output)
  }
  assemble_responses_output(message_parts, tool_outputs, reasoning_outputs~)
}

///|
fn build_responses_output_from_rich_content(
  parts : Array[@types.ResponseContentPart],
  annotations : Array[@types.ResponseAnnotation],
  tool_traces : Array[@types.ToolCallTrace],
) -> Array[Json] {
  let (message_parts, tool_outputs, reasoning_outputs) = decompose_responses_rich_content(
    parts, annotations, tool_traces,
  )
  assemble_responses_output(message_parts, tool_outputs, reasoning_outputs~)
}

///|
fn decompose_responses_rich_content(
  parts : Array[@types.ResponseContentPart],
  annotations : Array[@types.ResponseAnnotation],
  tool_traces : Array[@types.ToolCallTrace],
) -> (Array[Json], Array[Json], Array[Json]) {
  let message_parts : Array[Json] = []
  let reasoning_outputs : Array[Json] = []
  let tool_outputs : Array[Json] = []
  for trace in tool_traces {
    match trace.kind {
      @types.ToolCallKind::WebSearch =>
        tool_outputs.push({
          "type": "web_search_call",
          "id": trace.id,
          "status": tool_trace_status_to_json(trace.statuses),
          "action": @types.build_web_search_action(trace.arguments),
        })
      @types.ToolCallKind::Builtin(builtin_type~) =>
        tool_outputs.push(
          build_responses_builtin_tool_item(
            builtin_type,
            trace.id,
            trace.name,
            trace.arguments,
            statuses=trace.statuses,
          ),
        )
      _ => ()
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
          if annotation.start_index() >= seg_start &&
            annotation.end_index() <= seg_end {
            segment_annotations.push(annotation.to_interop_json())
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
      @types.ResponseContentPart::RedactedThinking(data~) =>
        reasoning_outputs.push(
          build_responses_reasoning_item("", encrypted_content=Some(data)),
        )
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
  (message_parts, tool_outputs, reasoning_outputs)
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
