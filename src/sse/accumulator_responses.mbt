///|
/// OpenAI/Groq Responses API stream accumulator

///|
/// OpenAI/Groq Responses API stream accumulator
/// Accumulates response.output_text.delta, response.function_call_arguments.delta, etc.
pub struct ResponsesApiAccumulator {
  text : StringBuilder
  function_calls : Array[ToolCallAcc]
  output_index_map : Map[String, Int]
  mut completed : Bool
}

///|
pub fn ResponsesApiAccumulator::new() -> ResponsesApiAccumulator {
  {
    text: StringBuilder::new(),
    function_calls: [],
    output_index_map: {},
    completed: false,
  }
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
          let call_index = self.function_calls.length()
          self.function_calls.push({ id, name, arguments: StringBuilder::new() })
          match event.data {
            { "output_index": Number(output_index, ..), .. } =>
              self.output_index_map[output_index.to_int().to_string()] = call_index
            _ => ()
          }
        }
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
                  let acc : ToolCallAcc = {
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
    @types.ModelResponse::ToolCalls(tool_calls_to_requests(self.function_calls))
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}
