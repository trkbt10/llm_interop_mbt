///|
/// Common accumulator utilities

///|
/// Process OpenAI-style tool_call delta
/// Used by ChatCompletionsAccumulator and HarmonyAccumulator
fn process_openai_tool_call_delta(
  tool_calls : Array[ToolCallAcc],
  tc : Json,
) -> Unit {
  let index = match tc {
    { "index": Number(n, ..), .. } => n.to_int()
    _ => if tool_calls.length() > 0 { tool_calls.length() - 1 } else { 0 }
  }
  if index < 0 {
    return
  }
  if tool_calls.length() <= index {
    for _ in tool_calls.length()..<=index {
      tool_calls.push({ id: "", name: "", arguments: StringBuilder::new() })
    }
  }
  match tc {
    { "id": String(id), .. } => tool_calls[index].id = id
    _ => ()
  }
  match tc {
    { "function": { "name": String(name), .. }, .. } =>
      tool_calls[index].name = name
    _ => ()
  }
  match tc {
    { "function": { "arguments": String(args), .. }, .. } =>
      tool_calls[index].arguments.write_string(args)
    _ => ()
  }
}

///|
/// Convert accumulated tool calls to ToolCallRequest array
fn tool_calls_to_requests(
  tool_calls : Array[ToolCallAcc],
) -> Array[@types.ToolCallRequest] {
  let calls : Array[@types.ToolCallRequest] = []
  for tc in tool_calls {
    let args_str = tc.arguments.to_string()
    let arguments : Json = @json.parse(args_str) catch { _ => {} }
    calls.push(@types.ToolCallRequest::new(id=tc.id, name=tc.name, arguments~))
  }
  calls
}
