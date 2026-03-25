///|
/// `claude mcp serve` ↔ OpenAI Chat Completions transforms
///
/// Request: OpenAI messages → prompt extraction (internal helper for tool dispatch)
/// Response: MCP tools/call result → OpenAI Chat Completion response

// =============================================================================
// Request transform: OpenAI → prompt extraction
// =============================================================================

///|
/// Extract the prompt text from an OpenAI Chat Completion request.
/// This is kept package-private; the public request-side entrypoint is
/// `prepare_chat_upstream(...)` in session.mbt.
fn extract_prompt_from_chat(
  body : String,
  _ctx : @types.TransformContext,
) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  let messages = match json {
    { "messages": Array(msgs), .. } => msgs
    _ => return None
  }
  Some(build_prompt_from_messages(messages))
}

///|
/// Build a prompt string from OpenAI messages (same logic as Codex).
fn build_prompt_from_messages(messages : Array[Json]) -> String {
  let mut system_msg = ""
  let mut last_user_msg = ""
  for msg in messages {
    match msg {
      { "role": String("system"), "content": String(text), .. } =>
        system_msg = text
      { "role": String("user"), "content": String(text), .. } =>
        last_user_msg = text
      { "role": String("user"), "content": Array(parts), .. } => {
        let buf = StringBuilder::new()
        for part in parts {
          match part {
            { "type": String("text"), "text": String(t), .. } => {
              if buf.to_string().length() > 0 {
                buf.write_string("\n")
              }
              buf.write_string(t)
            }
            _ =>
              abort(
                "`claude mcp serve` chat bridge cannot represent non-text user content without loss: " +
                part.stringify(),
              )
          }
        }
        last_user_msg = buf.to_string()
      }
      _ => ()
    }
  }
  if system_msg != "" && last_user_msg != "" {
    system_msg + "\n\n" + last_user_msg
  } else if last_user_msg != "" {
    last_user_msg
  } else {
    system_msg
  }
}

// =============================================================================
// Response transform: MCP result → OpenAI Chat Completion
// =============================================================================

///|
/// Transform a `claude mcp serve` tools/call result into an OpenAI Chat
/// completion response.
pub fn response_to_chat(
  body : String,
  id? : String = "claude-mcp-response",
  model? : String = "claude-code-tools",
) -> String {
  let response = model_response_from_tools_result(body)
  match response.as_failure() {
    Some(_) => ()
    None =>
      @openai_chat_contract.assert_model_response_is_chat_compatible(response)
  }
  let chat = @openai_chat_contract.model_response_to_chat_response(
    response,
    id~,
    model~,
  )
  let parsed = @json.parse(chat) catch { _ => return chat }
  match parsed {
    { "error": _, .. } => chat
    {
      "id": String(response_id),
      "object": String(object),
      "model": String(response_model),
      "choices": Array(choices),
      ..
    } =>
      Json::object({
        "id": Json::string(response_id),
        "object": Json::string(object),
        "model": Json::string(response_model),
        "choices": Json::array(choices),
        "usage": {
          "prompt_tokens": 0,
          "completion_tokens": 0,
          "total_tokens": 0,
        },
      }).stringify()
    _ => chat
  }
}

///|
pub fn parse_response(body : String) -> @types.ModelResponse {
  model_response_from_tools_result(body)
}

///|
pub fn response_to_responses(
  body : String,
  response_id~ : String,
  model? : String = "claude-code-tools",
) -> Json {
  @openai_responses_contract.model_response_to_responses_json(
    model_response_from_tools_result(body),
    response_id~,
    model~,
  )
}

///|
fn model_response_from_tools_result(body : String) -> @types.ModelResponse {
  let json = @json.parse(body) catch {
    _ =>
      return @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="`claude mcp serve` tools result bridge requires valid JSON",
          body=Some(body),
        ),
      )
  }
  let has_tool_content = match json {
    { "result": { "content": Array(_), .. }, .. } => true
    _ => false
  }
  match @mcp.parse_tools_call_result(json) {
    Some(result) =>
      if has_tool_content {
        let content = @mcp.extract_text_content(result)
        if result.is_error {
          @types.ModelResponse::Failure(
            failure=@types.ModelFailure::new(
              type_="claude_mcp_error",
              message=content,
              payload=Some(json),
              body=Some(body),
            ),
          )
        } else {
          @types.ModelResponse::Text(content)
        }
      } else {
        @types.ModelResponse::Failure(
          failure=@types.ModelFailure::parse_error(
            message="`claude mcp serve` tools result bridge requires a tools/call result payload",
            payload=Some(json),
            body=Some(body),
          ),
        )
      }
    None =>
      @types.ModelResponse::Failure(
        failure=@types.ModelFailure::parse_error(
          message="`claude mcp serve` tools result bridge requires a tools/call result payload",
          payload=Some(json),
          body=Some(body),
        ),
      )
  }
}
