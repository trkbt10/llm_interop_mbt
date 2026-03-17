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
  let messages = @harmony.responses_input_to_messages(input)
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
  let tool_defs = tools.map(fn(t) {
    match t {
      {
        "name": String(name),
        "description": String(desc),
        "parameters": params,
        ..
      } =>
        @types.ToolDefinition::new(name~, description=desc, parameters=params)
      _ =>
        @types.ToolDefinition::new(
          name="",
          description="",
          parameters=Json::object({}),
        )
    }
  })
  build_gemini_body(messages, tool_defs, max_tokens~)
}

///|
/// Convert Responses API tools to Gemini functionDeclarations format
fn convert_responses_tools_to_gemini(tools : Array[Json]) -> Array[Json] {
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
          "parameters": parameters,
        })
      }
      { "type": String("web_search_preview"), .. }
      | { "type": String("web_search_preview_2025_03_11"), .. } =>
        result.push(web_search_tool_for_gemini())
      _ => ()
    }
  }
  result
}

///|
fn web_search_tool_for_gemini() -> Json {
  {
    "name": "web_search",
    "description": "Search the web",
    "parameters": {
      "type": "object",
      "properties": { "query": { "type": "string" } },
      "required": Json::array([Json::string("query")]),
    },
  }
}
