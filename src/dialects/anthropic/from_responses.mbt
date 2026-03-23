///|
/// Responses API Request to Anthropic Messages API conversion
///
/// Enables using OpenAI Responses API as frontend with Anthropic Claude as backend.
/// Flow: Responses API Request -> Anthropic Messages Request

///|
/// Convert Responses API request JSON to Anthropic Messages API request body
pub fn responses_request_to_anthropic(request : Json) -> Json {
  let model = match request {
    { "model": String(m), .. } => m
    _ => ""
  }
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
    match tool {
      { "type": String("function"), "name": String(name), .. } => {
        let description = match tool {
          { "description": String(d), .. } => d
          _ => ""
        }
        let parameters = match tool {
          { "parameters": params, .. } => params
          _ => Json::object({})
        }
        result.push({
          "name": name,
          "description": description,
          "input_schema": parameters,
        })
      }
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
              name=extract_tool_name(tool, type_),
              config=extract_tool_config(tool),
            ),
          ),
        )
      _ => ()
    }
  }
  result
}

///|
fn extract_tool_name(tool : Json, fallback : String) -> String {
  match tool {
    { "name": String(name), .. } => name
    _ => fallback
  }
}

///|
fn extract_tool_config(tool : Json) -> Json {
  match tool {
    Object(fields) => {
      let config : Map[String, Json] = {}
      for key, value in fields {
        if key != "type" &&
          key != "name" &&
          key != "description" &&
          key != "parameters" {
          config[key] = value
        }
      }
      Json::object(config)
    }
    _ => Json::object({})
  }
}

///|
/// Convert Responses API request to Anthropic with streaming enabled
pub fn responses_request_to_anthropic_stream(request : Json) -> Json {
  let base = responses_request_to_anthropic(request)
  @utils.set_json_field(base, "stream", Json::boolean(true))
}
