///|
/// Anthropic Messages API Response to Responses API Response conversion
///
/// Converts Anthropic Claude responses to OpenAI Responses API format.
/// Flow: Anthropic Response -> Responses API Response

///|
/// Convert Anthropic Messages API response JSON to Responses API response JSON
pub fn response_to_responses(response : Json, response_id~ : String) -> Json {
  match response {
    { "content": Array(_), "model": String(model), .. } =>
      // SoT: reuse the canonical Anthropic parser plus the OpenAI Responses
      // serializer so rich annotations/tool traces stay aligned across direct,
      // synthetic-stream, and typed ModelResponse paths.
      @openai.model_response_to_responses_json(
        normalize_anthropic_model_response_for_responses(
          parse_response(response),
        ),
        response_id~,
        model~,
      )
    { "content": Array(_), .. } =>
      abort(
        "Anthropic success response is missing required model field: " +
        response.stringify(),
      )
    { "error": { "message": String(msg), .. }, .. } =>
      { "error": { "type": "error", "message": msg } }
    _ => { "error": { "type": "error", "message": "Unknown response format" } }
  }
}

///|
fn normalize_anthropic_model_response_for_responses(
  response : @types.ModelResponse,
) -> @types.ModelResponse {
  match response {
    @types.ModelResponse::ToolCalls(tool_calls) =>
      @types.ModelResponse::ToolCalls(
        tool_calls.map(normalize_anthropic_tool_call_for_responses),
      )
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      @types.ModelResponse::ToolCallsWithContent(
        tool_calls=tool_calls.map(normalize_anthropic_tool_call_for_responses),
        rich~,
      )
    _ => response
  }
}

///|
fn normalize_anthropic_tool_call_for_responses(
  call : @types.ToolCallRequest,
) -> @types.ToolCallRequest {
  {
    id: @interop_util.anthropic_to_openai_responses_call_id(call.id),
    name: call.name,
    arguments: call.arguments,
    kind: call.kind,
  }
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
