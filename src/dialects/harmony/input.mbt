///|
/// Responses API input to Chat Completions messages conversion

///|
/// Convert Responses API input items to Chat Completions messages format
/// input: [{ role: "user", content: "..." }, { type: "function_call", ... }, ...]
/// output: Array[@types.ModelMessage]
pub fn responses_input_to_messages(
  input : Array[Json],
) -> Array[@types.ModelMessage] {
  let messages : Array[@types.ModelMessage] = []
  let mut pending_tool_calls : Array[@types.ToolCallRequest] = []
  for item in input {
    match item {
      // System message
      { "role": String("system"), "content": content, .. } =>
        messages.push(@types.ModelMessage::System(extract_text_content(content)))
      // User message
      { "role": String("user"), "content": content, .. } => {
        // Flush any pending tool calls as assistant message
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        let content = extract_text_content(content)
        messages.push(@types.ModelMessage::User(content~, name=None))
      }
      // Assistant message (text only)
      { "role": String("assistant"), "content": content, .. } => {
        // Flush any pending tool calls first
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        let content = extract_text_content(content)
        messages.push(@types.ModelMessage::Assistant(content~, tool_calls=None))
      }
      // Function call (Responses API format)
      {
        "type": String("function_call"),
        "name": String(name),
        "arguments": String(args_str),
        ..
      } => {
        let id = match item {
          { "call_id": String(cid), .. } => cid
          { "id": String(fid), .. } => fid
          _ => ""
        }
        let arguments : Json = @json.parse(args_str) catch { _ => {} }
        pending_tool_calls.push(
          @types.ToolCallRequest::new(id~, name~, arguments~),
        )
      }
      // Built-in web search call (Responses API format)
      { "type": String("web_search_call"), "id": String(id), .. } => {
        let query = match item {
          { "action": { "query": String(q), .. }, .. } => Some(q)
          _ => None
        }
        let queries = match item {
          { "action": { "queries": Array(values), .. }, .. } =>
            Some(json_array_to_strings(values))
          _ => None
        }
        pending_tool_calls.push(
          @types.ToolCallRequest::web_search(id~, query~, queries~),
        )
      }
      // Function call output (Responses API format)
      {
        "type": String("function_call_output"),
        "call_id": String(call_id),
        "output": String(output),
        ..
      } => {
        // Flush pending tool calls as assistant message first
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        messages.push(
          @types.ModelMessage::ToolResult(tool_call_id=call_id, content=output),
        )
      }
      _ => () // Unknown item type, skip
    }
  }
  // Flush any remaining pending tool calls
  if pending_tool_calls.length() > 0 {
    messages.push(
      @types.ModelMessage::Assistant(
        content="",
        tool_calls=Some(pending_tool_calls),
      ),
    )
  }
  messages
}

///|
/// Extract text from content that can be either a plain string or
/// an array of content blocks (e.g. [{"type":"input_text","text":"..."}])
fn extract_text_content(content : Json) -> String {
  match content {
    String(s) => s
    Array(blocks) => {
      let buf = StringBuilder::new()
      for block in blocks {
        match block {
          // Responses API content block: {"type":"input_text","text":"..."}
          { "type": String("input_text"), "text": String(t), .. } =>
            buf.write_string(t)
          // Also handle {"type":"text","text":"..."} and {"type":"output_text","text":"..."}
          { "type": String("text"), "text": String(t), .. } =>
            buf.write_string(t)
          { "type": String("output_text"), "text": String(t), .. } =>
            buf.write_string(t)
          // Plain string in array
          String(t) => buf.write_string(t)
          _ => ()
        }
      }
      buf.to_string()
    }
    _ => ""
  }
}

///|
fn json_array_to_strings(items : Array[Json]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    match item {
      String(value) => result.push(value)
      _ => ()
    }
  }
  result
}
