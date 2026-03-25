///|
/// Responses API Request to Anthropic Messages API conversion
///
/// Enables using OpenAI Responses API as frontend with Anthropic Claude as backend.
/// Flow: Responses API Request -> Anthropic Messages Request

///|
/// Convert Responses API request JSON to Anthropic Messages API request body
pub fn responses_request_to_anthropic(request : Json) -> Json {
  let model = extract_responses_model_or_abort(request)
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
    @interop_util.ToolCallIdProvider::AnthropicClaude,
  )
  let msgs_json = messages_to_json(messages)
  // Extract system message
  let system = extract_system_message(messages)
  // Build Anthropic body
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs_json),
  }
  @types.GenerationParams::from_responses(request).apply_to_anthropic(body, {
    max_tokens: 8192,
    max_tokens_field: "max_tokens",
  })
  if system.length() > 0 {
    body["system"] = Json::string(system)
  }
  // Convert tools
  match request {
    { "tools": Array(tools), .. } =>
      if tools.length() > 0 {
        let anthropic_tools = convert_responses_tools_to_anthropic(tools)
        if anthropic_tools.length() > 0 {
          body["tools"] = Json::array(anthropic_tools)
        }
      }
    _ => ()
  }
  // Convert tool_choice
  match request {
    { "tool_choice": tool_choice, .. } => {
      let anthropic_choice = convert_tool_choice_to_anthropic(tool_choice)
      match anthropic_choice {
        Some(choice) => body["tool_choice"] = choice
        None => ()
      }
    }
    _ => ()
  }
  Json::object(body)
}

///|
/// Convert Responses API tools to Anthropic tools format
fn convert_responses_tools_to_anthropic(tools : Array[Json]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    match @utils.parse_responses_function_tool(tool) {
      Some((name, description, parameters)) =>
        result.push({
          "name": name,
          "description": description,
          "input_schema": parameters,
        })
      None =>
        match tool {
          { "type": String("web_search_preview"), .. }
          | { "type": String("web_search_preview_2025_03_11"), .. } =>
            result.push(
              tool_to_json(
                @types.ToolDefinition::builtin(
                  type_="web_search_20260209",
                  name=@types.web_search_tool_name(),
                ),
              ),
            )
          { "type": String(type_), .. } =>
            result.push(
              tool_to_json(
                @types.ToolDefinition::builtin(
                  type_~,
                  name=@utils.extract_responses_tool_name(tool),
                  config=@utils.extract_responses_tool_config(tool),
                ),
              ),
            )
          _ =>
            abort(
              "Responses tool cannot be translated to Anthropic: " +
              tool.stringify(),
            )
        }
    }
  }
  result
}

///|
fn extract_responses_model_or_abort(request : Json) -> String {
  match request {
    { "model": String(model), .. } => model
    _ =>
      abort(
        "Responses request is missing required model for Anthropic translation: " +
        request.stringify(),
      )
  }
}

///|
/// Convert Responses API request to Anthropic with streaming enabled
pub fn responses_request_to_anthropic_stream(request : Json) -> Json {
  let base = responses_request_to_anthropic(request)
  @utils.set_json_field(base, "stream", Json::boolean(true))
}
