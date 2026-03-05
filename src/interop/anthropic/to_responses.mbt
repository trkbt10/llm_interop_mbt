///|
/// Anthropic Messages API Response to Responses API Response conversion
///
/// Converts Anthropic Claude responses to OpenAI Responses API format.
/// Flow: Anthropic Response -> Responses API Response

///|
/// Convert Anthropic Messages API response JSON to Responses API response JSON
pub fn anthropic_response_to_responses(
  response : Json,
  response_id~ : String,
) -> Json {
  match response {
    { "content": Array(content_blocks), .. } => {
      let output = build_responses_output_from_anthropic(content_blocks)
      let model = match response {
        { "model": String(m), .. } => m
        _ => "unknown"
      }
      {
        "id": response_id,
        "object": "response",
        "status": "completed",
        "output": Json::array(output),
        "model": model,
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      { "error": { "type": "error", "message": msg } }
    _ => { "error": { "type": "error", "message": "Unknown response format" } }
  }
}

///|
/// Build Responses API output array from Anthropic content blocks
fn build_responses_output_from_anthropic(
  content_blocks : Array[Json],
) -> Array[Json] {
  let output : Array[Json] = []
  let text_parts : Array[Json] = []
  // Process content blocks
  for block in content_blocks {
    match block {
      { "type": String("text"), "text": String(text), .. } =>
        text_parts.push({ "type": "output_text", "text": text })
      {
        "type": String("tool_use"),
        "id": String(id),
        "name": String(name),
        "input": input,
        ..
      } => {
        // Convert Claude tool_use ID to Responses API call_id format
        let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
        output.push({
          "type": "function_call",
          "id": call_id,
          "call_id": call_id,
          "name": name,
          "arguments": input.stringify(),
          "status": "completed",
        })
      }
      _ => ()
    }
  }
  // Add message output if there's any text
  if text_parts.length() > 0 {
    // Insert message at the beginning
    let message_output : Array[Json] = [
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array(text_parts),
      },
    ]
    for o in output {
      message_output.push(o)
    }
    return message_output
  }
  output
}

///|
/// Parse Anthropic response JSON and convert to ModelResponse
pub fn parse_anthropic_as_model_response(
  response : Json,
) -> @types.ModelResponse {
  @protocol.parse_anthropic_response(response)
}

///|
/// Full pipeline: Parse Anthropic response and convert to Responses API JSON
pub fn anthropic_to_responses_full(
  response : Json,
  response_id~ : String,
) -> Json {
  // Option 1: Direct JSON conversion (preserves all details)
  anthropic_response_to_responses(response, response_id~)
}
