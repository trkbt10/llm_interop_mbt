///|
/// ModelResponse to Responses API JSON conversion

///|
/// Convert ModelResponse to Responses API response JSON
pub fn model_response_to_responses_json(
  response : @types.ModelResponse,
  response_id~ : String,
  model~ : String,
) -> Json {
  match response {
    @types.ModelResponse::Text(content) =>
      build_text_response_json(content, [], [], response_id, model)
    @types.ModelResponse::RichText(rich) =>
      match rich.content_parts {
        Some(parts) =>
          build_rich_response_json(
            parts,
            rich.annotations,
            rich.tool_traces,
            response_id,
            model,
          )
        None =>
          build_text_response_json(
            rich.content,
            rich.annotations,
            rich.tool_traces,
            response_id,
            model,
          )
      }
    @types.ModelResponse::ToolCalls(calls) => {
      let output : Array[Json] = []
      for call in calls {
        match call.kind {
          @types.ToolCallKind::Function =>
            output.push({
              "type": "function_call",
              "id": call.id,
              "call_id": call.id,
              "name": call.name,
              "arguments": call.arguments.stringify(),
              "status": "completed",
            })
          @types.ToolCallKind::WebSearch =>
            output.push({
              "type": "web_search_call",
              "id": call.id,
              "status": "completed",
              "action": @types.build_web_search_action(call.arguments),
            })
        }
      }
      {
        "id": response_id,
        "object": "response",
        "status": "completed",
        "output": Json::array(output),
        "model": model,
      }
    }
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
  }
}

///|
fn build_text_response_json(
  content : String,
  annotations : Array[@types.ResponseAnnotation],
  tool_traces : Array[@types.ToolCallTrace],
  response_id : String,
  model : String,
) -> Json {
  let output : Array[Json] = []
  for trace in tool_traces {
    if trace.kind == @types.ToolCallKind::WebSearch {
      output.push({
        "type": "web_search_call",
        "id": trace.id,
        "status": tool_trace_status_to_json(trace.statuses),
        "action": @types.build_web_search_action(trace.arguments),
      })
    }
  }
  output.push({
    "type": "message",
    "role": "assistant",
    "content": Json::array([
      {
        "type": "output_text",
        "text": content,
        "annotations": Json::array(annotations.map(annotation_to_json)),
      },
    ]),
  })
  {
    "id": response_id,
    "object": "response",
    "status": "completed",
    "output": Json::array(output),
    "model": model,
  }
}

///|
/// Convert ResponseContentPart array to Responses API output JSON.
/// Delegates to @openai.assemble_responses_output as the single source of truth
/// for Responses API output assembly.
///
/// Mapping:
///   OutputText → message.content output_text
///   OutputImage → message.content output_image
///   Refusal → message.content refusal
///   Thinking → reasoning item (via build_responses_reasoning_item)
///   RedactedThinking → skipped (no Responses API equivalent)
///   CodeExecution → message.content output_text (code block)
///   CodeResult → message.content output_text (execution result)
///   AudioOutput → message.content output_text (transcript)
fn build_rich_response_json(
  parts : Array[@types.ResponseContentPart],
  annotations : Array[@types.ResponseAnnotation],
  tool_traces : Array[@types.ToolCallTrace],
  response_id : String,
  model : String,
) -> Json {
  let text_parts : Array[Json] = []
  let reasoning_outputs : Array[Json] = []
  let tool_outputs : Array[Json] = []
  // Tool traces → tool_outputs
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
  // Compute character offset ranges for each OutputText part so annotations
  // can be assigned to the correct segment instead of being duplicated.
  let text_offsets : Array[(Int, Int)] = [] // (start_offset, end_offset)
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
  // ResponseContentPart → text_parts / reasoning_outputs
  let mut text_index = 0
  for part in parts {
    match part {
      @types.ResponseContentPart::OutputText(text) => {
        let (seg_start, seg_end) = text_offsets[text_index]
        let seg_annotations : Array[Json] = []
        for ann in annotations {
          match ann {
            @types.ResponseAnnotation::UrlCitation(start_index~, end_index~, ..) =>
              if start_index >= seg_start && end_index <= seg_end {
                seg_annotations.push(annotation_to_json(ann))
              }
          }
        }
        text_parts.push({
          "type": "output_text",
          "text": text,
          "annotations": Json::array(seg_annotations),
        })
        text_index = text_index + 1
      }
      @types.ResponseContentPart::OutputImage(url~) =>
        text_parts.push({ "type": "output_image", "image_url": url })
      @types.ResponseContentPart::Refusal(reason) =>
        text_parts.push({ "type": "refusal", "refusal": reason })
      @types.ResponseContentPart::Thinking(text~) =>
        reasoning_outputs.push(@openai.build_responses_reasoning_item(text))
      @types.ResponseContentPart::RedactedThinking(..) => ()
      @types.ResponseContentPart::CodeExecution(language~, code~) =>
        text_parts.push({
          "type": "output_text",
          "text": "```\{language}\n\{code}\n```",
        })
      @types.ResponseContentPart::CodeResult(outcome~, output~) =>
        text_parts.push({
          "type": "output_text",
          "text": "Execution [\{outcome}]: \{output}",
        })
      @types.ResponseContentPart::AudioOutput(transcript~, ..) =>
        text_parts.push({ "type": "output_text", "text": transcript })
    }
  }
  let output = @openai.assemble_responses_output(
    text_parts,
    tool_outputs,
    reasoning_outputs~,
  )
  {
    "id": response_id,
    "object": "response",
    "status": "completed",
    "output": Json::array(output),
    "model": model,
  }
}

///|
fn annotation_to_json(annotation : @types.ResponseAnnotation) -> Json {
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
