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
  // Get max_tokens
  let max_tokens : Int? = match request {
    { "max_output_tokens": Number(n, ..), .. } => Some(n.to_int())
    _ => None
  }
  // Build Gemini body using protocol
  let tools = match request {
    { "tools": Array(t), .. } => convert_responses_tools_to_gemini(t)
    _ => []
  }
  build_body(messages, tools, max_tokens~)
}

///|
/// Convert Responses API tools to Gemini ToolDefinition values
fn convert_responses_tools_to_gemini(
  tools : Array[Json],
) -> Array[@types.ToolDefinition] {
  let result : Array[@types.ToolDefinition] = []
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
        result.push(
          @types.ToolDefinition::new(name~, description~, parameters~),
        )
      }
      { "type": String("web_search_preview"), .. }
      | { "type": String("web_search_preview_2025_03_11"), .. } =>
        result.push(@types.ToolDefinition::web_search_preview())
      { "type": String(type_), .. } =>
        result.push(
          @types.ToolDefinition::builtin(
            type_~,
            config=extract_tool_config(tool),
          ),
        )
      _ => ()
    }
  }
  result
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
