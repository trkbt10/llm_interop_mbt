///|
/// Tool call delta accumulation
/// Used by all dialect stream accumulators

///|
/// Accumulates tool call deltas during streaming
pub(all) struct ToolCallAcc {
  mut id : String
  mut name : String
  arguments : StringBuilder
}

///|
/// Process a tool_call delta chunk (Chat Completions format)
pub fn process_tool_call_delta(
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
pub fn tool_calls_to_requests(
  tool_calls : Array[ToolCallAcc],
) -> Array[ToolCallRequest] {
  let calls : Array[ToolCallRequest] = []
  for tc in tool_calls {
    let args_str = tc.arguments.to_string()
    let arguments : Json = @json.parse(args_str) catch { _ => {} }
    calls.push(ToolCallRequest::new(id=tc.id, name=tc.name, arguments~))
  }
  calls
}
