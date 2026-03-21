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
  let messages = @harmony.responses_input_to_messages(input)
  let msgs_json = messages_to_json(messages)
  // Extract system message
  let system = extract_system_message(messages)
  // Get max_tokens (Anthropic requires this)
  let max_tokens = match request {
    { "max_output_tokens": Number(n, ..), .. } => n.to_int()
    _ => 8192
  }
  // Build Anthropic body
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs_json),
    "max_tokens": Json::number(max_tokens.to_double()),
  }
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
        result.push(web_search_tool_to_json())
      _ => ()
    }
  }
  result
}

///|
/// Convert Responses API tool_choice to Anthropic tool_choice format
fn convert_tool_choice_to_anthropic(tool_choice : Json) -> Json? {
  match tool_choice {
    String("auto") => Some({ "type": "auto" })
    String("none") => None // Anthropic doesn't have "none", just don't send tool_choice
    String("required") => Some({ "type": "any" })
    { "type": String("function"), "name": String(name), .. } =>
      Some({ "type": "tool", "name": name })
    _ => None
  }
}

///|
/// Convert Responses API request to Anthropic with streaming enabled
pub fn responses_request_to_anthropic_stream(request : Json) -> Json {
  let base = responses_request_to_anthropic(request)
  @utils.set_json_field(base, "stream", Json::boolean(true))
}
