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
      build_text_response_json(
        rich.content,
        rich.annotations,
        rich.tool_traces,
        response_id,
        model,
      )
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

