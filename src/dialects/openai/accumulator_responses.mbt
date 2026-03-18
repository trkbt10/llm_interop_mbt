///|
/// OpenAI/Groq Responses API stream accumulator

///|
/// OpenAI/Groq Responses API stream accumulator
/// Accumulates response.output_text.delta, response.function_call_arguments.delta, etc.
pub struct ResponsesApiAccumulator {
  text : StringBuilder
  annotations : Array[@types.ResponseAnnotation]
  function_calls : Array[@types.ToolCallAcc]
  output_index_map : Map[String, Int]
  web_search_traces : Array[WebSearchTraceAcc]
  mut completed : Bool
}

///|
struct WebSearchTraceAcc {
  id : String
  statuses : Array[@types.ToolCallStatus]
  arguments : Map[String, Json]
}

///|
/// Creates a new empty accumulator
pub fn ResponsesApiAccumulator::new() -> ResponsesApiAccumulator {
  {
    text: StringBuilder::new(),
    annotations: [],
    function_calls: [],
    output_index_map: {},
    web_search_traces: [],
    completed: false,
  }
}

///|
/// Process SSE event
pub fn ResponsesApiAccumulator::feed(
  self : ResponsesApiAccumulator,
  event : @sse.SseEvent,
) -> Unit {
  match event.event {
    "response.output_text.delta" =>
      match event.data {
        { "delta": String(delta), .. } => self.text.write_string(delta)
        _ => ()
      }
    "response.output_item.added" =>
      match event.data {
        {
          "item": { "type": String("function_call"), "name": String(name), .. } as item,
          ..
        } => {
          let id = match item {
            { "call_id": String(cid), .. } => cid
            { "id": String(fid), .. } => fid
            _ => ""
          }
          let call_index = self.function_calls.length()
          self.function_calls.push(@types.ToolCallAcc::{
            id,
            name,
            arguments: StringBuilder::new(),
          })
          match event.data {
            { "output_index": Number(output_index, ..), .. } =>
              self.output_index_map[output_index.to_int().to_string()] = call_index
            _ => ()
          }
        }
        { "item": { "type": String("web_search_call"), .. } as item, .. } => {
          let id = match item {
            { "id": String(fid), .. } => fid
            _ => ""
          }
          let _ = self.ensure_web_search_trace(id)
        }
        _ => ()
      }
    "response.output_text.annotation.added" =>
      match event.data {
        { "annotation": annotation, .. } =>
          push_annotations(self.annotations, parse_annotations(annotation))
        _ => ()
      }
    "response.function_call_arguments.delta" =>
      match event.data {
        { "delta": String(delta), .. } =>
          if self.function_calls.length() > 0 {
            let call_index = match event.data {
              { "output_index": Number(output_index, ..), .. } =>
                self.output_index_map.get(output_index.to_int().to_string())
              _ => None
            }
            match call_index {
              Some(i) => self.function_calls[i].arguments.write_string(delta)
              None =>
                self.function_calls[self.function_calls.length() - 1].arguments.write_string(
                  delta,
                )
            }
          }
        _ => ()
      }
    "response.web_search_call.in_progress" =>
      match event.data {
        { "item_id": String(item_id), .. } =>
          self.append_web_search_status(
            item_id,
            @types.ToolCallStatus::InProgress,
          )
        _ => ()
      }
    "response.web_search_call.searching" =>
      match event.data {
        { "item_id": String(item_id), .. } =>
          self.append_web_search_status(
            item_id,
            @types.ToolCallStatus::Searching,
          )
        _ => ()
      }
    "response.web_search_call.completed" =>
      match event.data {
        { "item_id": String(item_id), .. } =>
          self.append_web_search_status(
            item_id,
            @types.ToolCallStatus::Completed,
          )
        _ => ()
      }
    "response.output_item.done" =>
      match event.data {
        {
          "item": {
            "type": String("function_call"),
            "name": String(name),
            "arguments": String(arguments),
            ..
          } as item,
          ..
        } => {
          let id = match item {
            { "call_id": String(cid), .. } => cid
            { "id": String(fid), .. } => fid
            _ => ""
          }
          match event.data {
            { "output_index": Number(output_index, ..), .. } => {
              let key = output_index.to_int().to_string()
              match self.output_index_map.get(key) {
                Some(i) => {
                  self.function_calls[i].id = id
                  self.function_calls[i].name = name
                  if self.function_calls[i].arguments.to_string().length() == 0 &&
                    arguments.length() > 0 {
                    self.function_calls[i].arguments.write_string(arguments)
                  }
                }
                None => {
                  let call_index = self.function_calls.length()
                  let acc : @types.ToolCallAcc = {
                    id,
                    name,
                    arguments: StringBuilder::new(),
                  }
                  if arguments.length() > 0 {
                    acc.arguments.write_string(arguments)
                  }
                  self.function_calls.push(acc)
                  self.output_index_map[key] = call_index
                }
              }
            }
            _ => ()
          }
        }
        {
          "item": { "type": String("web_search_call"), "id": String(id), .. } as item,
          ..
        } => {
          let index = self.ensure_web_search_trace(id)
          match item {
            { "action": { "query": String(query), .. }, .. } =>
              self.web_search_traces[index].arguments["query"] = Json::string(
                query,
              )
            _ => ()
          }
          match item {
            { "action": { "queries": Array(queries), .. }, .. } =>
              self.web_search_traces[index].arguments["queries"] = Json::array(
                queries,
              )
            _ => ()
          }
          if not(
              self.web_search_traces[index].statuses.contains(
                @types.ToolCallStatus::Completed,
              ),
            ) {
            self.web_search_traces[index].statuses.push(
              @types.ToolCallStatus::Completed,
            )
          }
        }
        {
          "item": { "type": String("message"), "content": Array(contents), .. },
          ..
        } =>
          for content in contents {
            match content {
              { "type": String("output_text"), "annotations": Array(items), .. } =>
                push_annotations(
                  self.annotations,
                  parse_annotation_array(items),
                )
              _ => ()
            }
          }
        _ => ()
      }
    "response.completed" => self.completed = true
    _ => () // reasoning, content_part, ping, etc.
  }
}

///|
/// Get final result
pub fn ResponsesApiAccumulator::finish(
  self : ResponsesApiAccumulator,
) -> @types.ModelResponse {
  if self.function_calls.length() > 0 {
    @types.ModelResponse::ToolCalls(
      @types.tool_calls_to_requests(self.function_calls),
    )
  } else if self.annotations.length() > 0 || self.web_search_traces.length() > 0 {
    @types.ModelResponse::RichText(
      @types.RichTextResponse::new(
        content=self.text.to_string(),
        annotations=self.annotations,
        tool_traces=self.web_search_traces.map(web_search_trace_to_public),
      ),
    )
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}

///|
fn ResponsesApiAccumulator::ensure_web_search_trace(
  self : ResponsesApiAccumulator,
  id : String,
) -> Int {
  for i = 0; i < self.web_search_traces.length(); i = i + 1 {
    if self.web_search_traces[i].id == id {
      return i
    }
  }
  let index = self.web_search_traces.length()
  self.web_search_traces.push({ id, statuses: [], arguments: {} })
  index
}

///|
fn ResponsesApiAccumulator::append_web_search_status(
  self : ResponsesApiAccumulator,
  id : String,
  status : @types.ToolCallStatus,
) -> Unit {
  let index = self.ensure_web_search_trace(id)
  self.web_search_traces[index].statuses.push(status)
}

///|
fn web_search_trace_to_public(
  trace : WebSearchTraceAcc,
) -> @types.ToolCallTrace {
  @types.ToolCallTrace::new(
    id=trace.id,
    name="web_search",
    kind=@types.ToolCallKind::WebSearch,
    statuses=trace.statuses,
    arguments=Json::object(trace.arguments),
  )
}

///|
fn parse_annotations(annotation : Json) -> Array[@types.ResponseAnnotation] {
  match annotation {
    Array(items) => parse_annotation_array(items)
    _ => parse_annotation_array([annotation])
  }
}

///|
fn parse_annotation_array(
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
fn push_annotations(
  target : Array[@types.ResponseAnnotation],
  incoming : Array[@types.ResponseAnnotation],
) -> Unit {
  for annotation in incoming {
    target.push(annotation)
  }
}
