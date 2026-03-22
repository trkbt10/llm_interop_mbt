///|
/// OpenAI/Groq Responses API stream accumulator
///
/// SSE event flow (Ref: docs/upstream/openai-responses-create.md:13556-13584):
///   response.created → response.in_progress
///   → response.output_item.added (message/reasoning/function_call/web_search_call)
///   → response.content_part.added (empty shell — text:"", annotations:[])
///     Ref: docs/upstream/openai-responses-create.md:13566-13567
///   → response.output_text.delta / response.refusal.delta (incremental text)
///   → response.content_part.done (completed part with final text)
///     Ref: docs/upstream/openai-responses-create.md:13577-13578
///   → response.output_item.done (completed item containing all content parts)
///     Ref: docs/upstream/openai-responses-create.md:13580-13581
///   → response.completed
///
/// content_part.added is an empty shell (text:""), NOT the final content.
/// content_part.done and output_item.done both carry the completed content.
/// To avoid double-counting, structured content parts (refusal, output_image)
/// are extracted exclusively from output_item.done.
///
/// NOTE: output_image is not present in the vendored snapshot
/// (docs/upstream/openai-responses-create.md). Its structure is inferred from
/// the ResponseOutputMessage schema at line 336 ("content: array of
/// ResponseOutputText or ResponseOutputRefusal") and runtime payloads from
/// image generation models. If the snapshot is updated to include output_image
/// examples, this comment should be revised with exact line references.

///|
/// OpenAI/Groq Responses API stream accumulator
pub struct ResponsesApiAccumulator {
  text : StringBuilder
  /// Refusal delta accumulator — used only if output_item.done lacks refusal
  refusal : StringBuilder
  annotations : Array[@types.ResponseAnnotation]
  function_calls : Array[@types.ToolCallAcc]
  output_index_map : Map[String, Int]
  web_search_traces : Array[WebSearchTraceAcc]
  /// Structured content parts extracted from output_item.done (authoritative)
  content_parts : Array[@types.ResponseContentPart]
  mut has_non_text : Bool
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
    refusal: StringBuilder::new(),
    annotations: [],
    function_calls: [],
    output_index_map: {},
    web_search_traces: [],
    content_parts: [],
    has_non_text: false,
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
    // --- Delta events: accumulate text incrementally ---
    // Ref: docs/upstream/openai-responses-create.md:13569
    "response.output_text.delta" =>
      match event.data {
        { "delta": String(delta), .. } => self.text.write_string(delta)
        _ => ()
      }
    // Ref: docs/upstream/openai-responses-create.md:13569 (refusal variant)
    "response.refusal.delta" =>
      match event.data {
        { "delta": String(delta), .. } => self.refusal.write_string(delta)
        _ => ()
      }
    "response.refusal.done" => ()
    // --- Annotation events ---
    "response.output_text.annotation.added" =>
      match event.data {
        { "annotation": annotation, .. } =>
          push_annotations(self.annotations, parse_annotations(annotation))
        _ => ()
      }
    // --- Function call delta ---
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
    // --- output_item.added: set up tracking for new items ---
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
    // --- Web search status events ---
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
    // --- output_item.done: authoritative final snapshot ---
    // content_part.added is an empty shell (line 13567), content_part.done has the
    // completed part (line 13578), and output_item.done has all parts (line 13581).
    // We use output_item.done as the authoritative ordered list of message parts.
    // Ref: docs/upstream/openai-responses-create.md:13580-13581
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
        // Ref: ResponseOutputMessage — extract refusal, output_image from content
        // Ref: docs/upstream/openai-responses-create.md:13580
        {
          "item": { "type": String("message"), "content": Array(contents), .. },
          ..
        } => {
          let message_parts : Array[@types.ResponseContentPart] = []
          let mut saw_output_text = false
          for content in contents {
            match content {
              { "type": String("output_text"), "text": String(text), .. } => {
                saw_output_text = true
                if text.length() > 0 {
                  message_parts.push(
                    @types.ResponseContentPart::OutputText(text),
                  )
                }
                match content {
                  { "annotations": Array(items), .. } =>
                    push_annotations(
                      self.annotations,
                      parse_annotation_array(items),
                    )
                  _ => ()
                }
              }
              // Ref: docs/upstream/openai-responses-create.md:470-482 — ResponseOutputRefusal
              { "type": String("refusal"), "refusal": String(reason), .. } =>
                message_parts.push(@types.ResponseContentPart::Refusal(reason))
              // NOTE: output_image is not in vendored snapshot; inferred from
              // ResponseOutputMessage schema (line 336) and runtime payloads
              { "type": String("output_image"), "image_url": String(url), .. } =>
                message_parts.push(
                  @types.ResponseContentPart::OutputImage(url~),
                )
              _ => ()
            }
          }
          if saw_output_text {
            // output_item.done carries the final text segments in order, so the
            // delta buffer is only needed as a fallback when that snapshot is absent.
            self.text.reset()
          }
          for part in message_parts {
            match part {
              @types.ResponseContentPart::Refusal(_)
              | @types.ResponseContentPart::OutputImage(..) =>
                self.has_non_text = true
              _ => ()
            }
            self.content_parts.push(part)
          }
        }
        // Ref: ResponseReasoningItem — extract thinking from summary/content
        // Ref: docs/upstream/openai-responses-create.md:2459-2497
        //   summary: array of SummaryTextContent (line 2459)
        //   content: optional array of {text, type:"reasoning_text"} (line 2479-2489)
        { "item": { "type": String("reasoning"), .. } as item, .. } => {
          let mut found = false
          // Prefer content array (detailed reasoning_text)
          match item {
            { "content": Array(content_blocks), .. } =>
              for cblock in content_blocks {
                match cblock {
                  { "type": String("reasoning_text"), "text": String(t), .. } => {
                    self.content_parts.push(
                      @types.ResponseContentPart::Thinking(text=t),
                    )
                    self.has_non_text = true
                    found = true
                  }
                  _ => ()
                }
              }
            _ => ()
          }
          // Fallback to summary array
          if not(found) {
            match item {
              { "summary": Array(summary_blocks), .. } =>
                for sblock in summary_blocks {
                  match sblock {
                    { "type": String("summary_text"), "text": String(t), .. } => {
                      self.content_parts.push(
                        @types.ResponseContentPart::Thinking(text=t),
                      )
                      self.has_non_text = true
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
    // --- content_part.added/done: NOT used for content_parts extraction ---
    // content_part.added is an empty shell (line 13567: text:"", annotations:[]).
    // content_part.done has the completed part (line 13578) but output_item.done
    // (line 13581) also includes it, so we skip both to avoid double-counting.
    // Ref: docs/upstream/openai-responses-create.md:13566-13578
    "response.content_part.added" | "response.content_part.done" => ()
    // --- Reasoning delta: no-op, captured on output_item.done ---
    "response.reasoning_summary_text.delta"
    | "response.reasoning_summary_text.done" => ()
    "response.output_text.done" => ()
    "response.completed" => self.completed = true
    _ => () // response.created, response.in_progress, ping, etc.
  }
}

///|
/// Flush accumulated text into content_parts, preserving interleaving order
/// with non-text parts (images, refusals). Resets the text buffer.
fn ResponsesApiAccumulator::flush_text(self : ResponsesApiAccumulator) -> Unit {
  let text_str = self.text.to_string()
  if text_str.length() > 0 {
    self.content_parts.push(@types.ResponseContentPart::OutputText(text_str))
    self.text.reset()
  }
}

///|
/// Get final result
pub fn ResponsesApiAccumulator::finish(
  self : ResponsesApiAccumulator,
) -> @types.ModelResponse {
  // Flush any remaining text into content_parts (preserves interleaving order)
  self.flush_text()
  // Reconstruct full text for the content field (concatenate all OutputText parts)
  let full_text = StringBuilder::new()
  for p in self.content_parts {
    match p {
      @types.ResponseContentPart::OutputText(t) => full_text.write_string(t)
      _ => ()
    }
  }
  let text_str = full_text.to_string()
  // If refusal was accumulated via delta but NOT captured by output_item.done,
  // add it as a fallback. This handles edge cases where output_item.done
  // arrives without the message content (e.g. incomplete streams).
  let refusal_str = self.refusal.to_string()
  if refusal_str.length() > 0 {
    let mut already_has_refusal = false
    for p in self.content_parts {
      match p {
        @types.ResponseContentPart::Refusal(_) => {
          already_has_refusal = true
          break
        }
        _ => ()
      }
    }
    if not(already_has_refusal) {
      self.content_parts.push(@types.ResponseContentPart::Refusal(refusal_str))
      self.has_non_text = true
    }
  }
  if self.function_calls.length() > 0 {
    @types.ModelResponse::ToolCalls(
      @types.tool_calls_to_requests(self.function_calls),
    )
  } else if self.has_non_text ||
    self.annotations.length() > 0 ||
    self.web_search_traces.length() > 0 {
    let parts = if self.has_non_text { Some(self.content_parts) } else { None }
    @types.ModelResponse::RichText(
      @types.RichTextResponse::new(
        content=text_str,
        content_parts=parts,
        annotations=self.annotations,
        tool_traces=self.web_search_traces.map(web_search_trace_to_public),
      ),
    )
  } else {
    @types.ModelResponse::Text(text_str)
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
    name=@types.web_search_tool_name(),
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
    if not(target.contains(annotation)) {
      target.push(annotation)
    }
  }
}
