///|
/// Common accumulator utilities

///|
/// Process OpenAI-style tool_call delta
/// Used by ChatCompletionsAccumulator and HarmonyAccumulator
fn process_openai_tool_call_delta(
  tool_calls : Array[ToolCallAcc],
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
      tool_calls.push(acc)
    }
    { "function": { "arguments": String(args), .. }, .. } =>
      // Append arguments to existing tool call
      if tool_calls.length() > 0 {
        tool_calls[tool_calls.length() - 1].arguments.write_string(args)
      }
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
