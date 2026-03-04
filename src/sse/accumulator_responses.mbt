///|
/// OpenAI/Groq Responses API stream accumulator

///|
/// OpenAI/Groq Responses API stream accumulator
/// Accumulates response.output_text.delta, response.function_call_arguments.delta, etc.
pub struct ResponsesApiAccumulator {
  text : StringBuilder
  function_calls : Array[ToolCallAcc]
  mut completed : Bool
}

///|
pub fn ResponsesApiAccumulator::new() -> ResponsesApiAccumulator {
  { text: StringBuilder::new(), function_calls: [], completed: false }
}

///|
/// Process SSE event
pub fn ResponsesApiAccumulator::feed(
  self : ResponsesApiAccumulator,
  event : SseEvent,
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
          self.function_calls.push({ id, name, arguments: StringBuilder::new() })
        }
        _ => ()
      }
    "response.function_call_arguments.delta" =>
      match event.data {
        { "delta": String(delta), .. } =>
          if self.function_calls.length() > 0 {
            self.function_calls[self.function_calls.length() - 1].arguments.write_string(
              delta,
            )
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
    let calls : Array[@types.ToolCallRequest] = []
    for fc in self.function_calls {
      let args_str = fc.arguments.to_string()
      let arguments : Json = @json.parse(args_str) catch { _ => {} }
      calls.push(
        @types.ToolCallRequest::new(id=fc.id, name=fc.name, arguments~),
      )
    }
    @types.ModelResponse::ToolCalls(calls)
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}
