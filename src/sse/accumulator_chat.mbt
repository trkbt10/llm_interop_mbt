///|
/// OpenAI Chat Completions stream accumulator

///|
/// OpenAI Chat Completions stream accumulator
/// Accumulates text and tool calls from choices[0].delta
pub struct ChatCompletionsAccumulator {
  text : StringBuilder
  tool_calls : Array[ToolCallAcc]
  mut finish_reason : String
}

///|
pub fn ChatCompletionsAccumulator::new() -> ChatCompletionsAccumulator {
  { text: StringBuilder::new(), tool_calls: [], finish_reason: "" }
}

///|
/// Process chunk event
pub fn ChatCompletionsAccumulator::feed(
  self : ChatCompletionsAccumulator,
  event : SseEvent,
) -> Unit {
  match event.data {
    { "choices": Array(choices), .. } =>
      if choices.length() > 0 {
        let choice = choices[0]
        match choice {
          { "delta": delta, .. } => {
            // Text delta
            match delta {
              { "content": String(content), .. } =>
                self.text.write_string(content)
              _ => ()
            }
            // Tool calls delta
            match delta {
              { "tool_calls": Array(tc_deltas), .. } =>
                for tc in tc_deltas {
                  self.process_tool_call_delta(tc)
                }
              _ => ()
            }
          }
          _ => ()
        }
        // finish_reason
        match choice {
          { "finish_reason": String(fr), .. } => self.finish_reason = fr
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn ChatCompletionsAccumulator::process_tool_call_delta(
  self : ChatCompletionsAccumulator,
  tc : Json,
) -> Unit {
  match tc {
    { "id": String(id), "function": { "name": String(name), .. }, .. } => {
      // New tool call
      let acc : ToolCallAcc = { id, name, arguments: StringBuilder::new() }
      match tc {
        { "function": { "arguments": String(args), .. }, .. } =>
          acc.arguments.write_string(args)
        _ => ()
      }
      self.tool_calls.push(acc)
    }
    { "function": { "arguments": String(args), .. }, .. } =>
      // Append arguments to existing tool call
      if self.tool_calls.length() > 0 {
        self.tool_calls[self.tool_calls.length() - 1].arguments.write_string(
          args,
        )
      }
    _ => ()
  }
}

///|
/// Get final result
pub fn ChatCompletionsAccumulator::finish(
  self : ChatCompletionsAccumulator,
) -> @types.ModelResponse {
  if self.finish_reason == "tool_calls" && self.tool_calls.length() > 0 {
    let calls : Array[@types.ToolCallRequest] = []
    for tc in self.tool_calls {
      let args_str = tc.arguments.to_string()
      let arguments : Json = @json.parse(args_str) catch { _ => {} }
      calls.push(
        @types.ToolCallRequest::new(id=tc.id, name=tc.name, arguments~),
      )
    }
    @types.ModelResponse::ToolCalls(calls)
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}
