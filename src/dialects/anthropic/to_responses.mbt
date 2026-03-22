///|
/// Anthropic Messages API Response to Responses API Response conversion
///
/// Converts Anthropic Claude responses to OpenAI Responses API format.
/// Flow: Anthropic Response -> Responses API Response

///|
/// Convert Anthropic Messages API response JSON to Responses API response JSON
pub fn response_to_responses(response : Json, response_id~ : String) -> Json {
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
  let tool_outputs : Array[Json] = []
  let text_parts : Array[Json] = []
  // Anthropic content blocks → Responses API output items
  // Ref: https://platform.claude.com/docs/en/api/messages
  //   TextBlock → output_text
  //   ThinkingBlock → reasoning (Ref: ResponseReasoningItem)
  //   RedactedThinkingBlock → not representable in Responses API, skipped
  //   ToolUseBlock → function_call / web_search_call
  //   CodeExecutionToolResultBlock → output_text (text representation)
  let reasoning_outputs : Array[Json] = []
  for block in content_blocks {
    match block {
      // Ref: TextBlock — {"type":"text","text":"..."} → output_text
      { "type": String("text"), "text": String(text), .. } =>
        text_parts.push({ "type": "output_text", "text": text })
      // ThinkingBlock: {"type":"thinking","thinking":"...","signature":"..."}
      // Ref: docs/upstream/anthropic-messages-api.md:3971-3979
      //   ThinkingBlock = object { signature, thinking, type }
      { "type": String("thinking"), "thinking": String(thinking_text), .. } =>
        reasoning_outputs.push(
          @openai.build_responses_reasoning_item(thinking_text),
        )
      // RedactedThinkingBlock: no Responses API equivalent
      { "type": String("redacted_thinking"), .. } => ()
      // CodeExecutionToolResultBlock
      // Ref: docs/upstream/anthropic-messages-api.md:1911-1977
      //   CodeExecutionToolResultBlockParam = object { content, tool_use_id, type }
      // Ref: docs/upstream/anthropic-code-execution-tool.md:1796-1802
      //   {"type":"bash_code_execution_tool_result","content":{"stdout":"...","stderr":"","return_code":0}}
      {
        "type": String("code_execution_tool_result"),
        "content": content_obj,
        ..
      } => {
        let stdout = match content_obj {
          { "stdout": String(s), .. } => s
          _ => ""
        }
        let stderr = match content_obj {
          { "stderr": String(s), .. } => s
          _ => ""
        }
        let output = if stdout.length() > 0 && stderr.length() > 0 {
          "Code execution output:\n\{stdout}\n[stderr]\n\{stderr}"
        } else if stderr.length() > 0 {
          "Code execution [stderr]:\n\{stderr}"
        } else if stdout.length() > 0 {
          "Code execution output:\n\{stdout}"
        } else {
          "Code execution completed (no output)"
        }
        text_parts.push({ "type": "output_text", "text": output })
      }
      // ToolUseBlock: {"type":"tool_use","id":"...","name":"...","input":{}}
      {
        "type": String("tool_use"),
        "id": String(id),
        "name": String(name),
        "input": input,
        ..
      } => {
        let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
        if name == @types.web_search_tool_name() {
          tool_outputs.push(
            @openai.build_responses_web_search_call(call_id, input),
          )
        } else {
          tool_outputs.push(
            @openai.build_responses_function_call(call_id, name, input),
          )
        }
      }
      _ => ()
    }
  }
  @openai.assemble_responses_output(
    text_parts,
    tool_outputs,
    reasoning_outputs~,
  )
}

///|
/// Parse Anthropic response JSON and convert to ModelResponse
pub fn parse_anthropic_as_model_response(
  response : Json,
) -> @types.ModelResponse {
  parse_response(response)
}

///|
/// Full pipeline: Parse Anthropic response and convert to Responses API JSON
pub fn anthropic_to_responses_full(
  response : Json,
  response_id~ : String,
) -> Json {
  // Option 1: Direct JSON conversion (preserves all details)
  response_to_responses(response, response_id~)
}
