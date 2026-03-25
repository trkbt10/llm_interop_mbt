///|
/// Responses API Request to Gemini GenerateContent API conversion
///
/// Enables using OpenAI Responses API as frontend with Google Gemini as backend.
/// Flow: Responses API Request -> Gemini GenerateContent Request

///|
/// Convert Responses API request JSON to Gemini GenerateContent API request body
pub fn responses_request_to_gemini(request : Json) -> Json {
  let input = match request {
    { "input": Array(items), .. } => items
    _ => []
  }
  let messages : Array[@types.ModelMessage] = []
  match request {
    { "instructions": String(instructions), .. } =>
      messages.push(@types.ModelMessage::System(instructions))
    _ => ()
  }
  for message in @harmony.responses_input_to_messages(input) {
    messages.push(message)
  }
  let messages = @interop_util.convert_message_tool_call_ids(
    messages,
    @interop_util.ToolCallIdProvider::GoogleGemini,
  )
  let tools = match request {
    { "tools": Array(t), .. } => convert_responses_tools_to_gemini(t)
    _ => []
  }
  let body = build_body(messages, tools)
  match body {
    Object(obj) => {
      @types.GenerationParams::from_responses(request).apply_to_gemini(
        obj,
        @types.TransformContext::default(),
      )
      Json::object(obj)
    }
    _ => body
  }
}

///|
/// Convert Responses API tools to Gemini ToolDefinition values
fn convert_responses_tools_to_gemini(
  tools : Array[Json],
) -> Array[@types.ToolDefinition] {
  let result : Array[@types.ToolDefinition] = []
  for tool in tools {
    match @utils.parse_responses_function_tool(tool) {
      Some((name, description, parameters)) =>
        result.push(
          @types.ToolDefinition::new(name~, description~, parameters~),
        )
      None =>
        match tool {
          { "type": String("web_search_preview"), .. }
          | { "type": String("web_search_preview_2025_03_11"), .. } =>
            result.push(@types.ToolDefinition::web_search_preview())
          { "type": String(type_), .. } =>
            result.push(
              @types.ToolDefinition::builtin(
                type_~,
                config=@utils.extract_responses_tool_config(tool),
              ),
            )
          _ =>
            abort(
              "Responses tool cannot be translated to Gemini: " +
              tool.stringify(),
            )
        }
    }
  }
  result
}
