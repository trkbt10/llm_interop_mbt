///|
fn extract_tool_call(
  response : @types.ModelResponse,
) -> ExtractedToolCall raise LiveCheckError {
  match response.as_failure() {
    Some(failure) =>
      match failure.retry_after {
        Some(retry_after) if failure.type_ == "rate_limit_error" =>
          raise ModelUnavailable("rate limited: retry_after=\{retry_after}")
        _ =>
          raise ValidationFailed(
            "expected tool call response, got failure [\{failure.type_}]: " +
              failure.message,
          )
      }
    None => ()
  }
  match response {
    @types.ModelResponse::ToolCalls(calls) =>
      if calls.length() > 0 {
        { call: calls[0], assistant_content: "" }
      } else {
        raise ValidationFailed("expected at least one tool call")
      }
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      if tool_calls.length() > 0 {
        { call: tool_calls[0], assistant_content: rich.content }
      } else {
        raise ValidationFailed("expected at least one tool call")
      }
    _ => raise ValidationFailed("expected tool call response")
  }
}

///|
fn validate_extracted_tool_call(
  extracted : ExtractedToolCall,
  label : String,
) -> Unit raise LiveCheckError {
  if extracted.call.id.length() == 0 {
    raise ValidationFailed("tool call id was empty")
  }
  if extracted.call.name != "lookup_verification_url" {
    raise ValidationFailed("unexpected tool name: " + extracted.call.name)
  }
  if not(extracted.call.arguments.stringify().contains(label)) {
    raise ValidationFailed(
      "tool call arguments did not preserve expected label: " +
        extracted.call.arguments.stringify(),
    )
  }
}

///|
fn tool_followup_carrier_summary(
  api : @gateway.ModelApi,
  body : String,
  call_id : String,
) -> String raise LiveCheckError {
  match api {
    @gateway.OpenAIResponses => {
      if not(body.contains("\"function_call_output\"")) {
        raise ValidationFailed("OpenAI followup request missed function_call_output")
      }
      if not(body.contains("\"call_id\":\"\{call_id}\"")) {
        raise ValidationFailed("OpenAI followup request missed original call_id")
      }
      "toolcall followup openai call_id preserved"
    }
    @gateway.AnthropicMessages => {
      if not(body.contains("\"tool_result\"")) {
        raise ValidationFailed("Anthropic followup request missed tool_result block")
      }
      let expected_native_id = @interop_util.convert_tool_call_id_to(
        call_id,
        @interop_util.ToolCallIdProvider::AnthropicClaude,
      )
      let has_raw_id = body.contains("\"tool_use_id\":\"\{call_id}\"")
      let has_native_id = body.contains("\"tool_use_id\":\"\{expected_native_id}\"")
      if not(has_raw_id || has_native_id) {
        raise ValidationFailed(
          "Anthropic followup request missed consistent tool_use_id expected_raw=\{call_id} expected_native=\{expected_native_id} body=\{body}",
        )
      }
      "toolcall followup anthropic tool_use_id mapped"
    }
    @gateway.GoogleGenerativeAI => {
      if not(body.contains("\"functionResponse\"")) {
        raise ValidationFailed("Gemini followup request missed functionResponse")
      }
      if not(body.contains("\"lookup_verification_url\"")) {
        raise ValidationFailed("Gemini followup request missed functionResponse name")
      }
      "toolcall followup gemini functionResponse mapped"
    }
    _ => "toolcall followup"
  }
}
