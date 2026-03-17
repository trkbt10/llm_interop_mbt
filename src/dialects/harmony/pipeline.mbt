///|
/// Full pipeline: Responses API Request -> Chat Completions -> Responses API Response

///|
/// Convert Responses API request to Chat Completions request body
pub fn responses_request_to_chat_completions(
  request : Json,
  stream? : Bool = true,
) -> Json {
  let model = match request {
    { "model": String(m), .. } => m
    _ => ""
  }
  let messages = match request {
    { "input": Array(items), .. } => responses_input_to_messages(items)
    { "input": String(text), .. } =>
      [@types.ModelMessage::User(content=text, name=None)]
    _ => []
  }
  let msgs_json = @openai.messages_to_openai_json(messages)
  // Build Chat Completions body
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs_json),
    "stream": Json::boolean(stream),
  }
  // Convert tools
  match request {
    { "tools": Array(tools), .. } =>
      if tools.length() > 0 {
        body["tools"] = Json::array(convert_responses_tools_to_chat(tools))
        body["tool_choice"] = Json::string("auto")
      }
    _ => ()
  }
  Json::object(body)
}

///|
fn convert_responses_tools_to_chat(tools : Array[Json]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    match tool {
      { "type": String("web_search_preview"), .. }
      | { "type": String("web_search_preview_2025_03_11"), .. } =>
        result.push({
          "type": "function",
          "function": {
            "name": "web_search",
            "description": "Search the web",
            "parameters": {
              "type": "object",
              "properties": { "query": { "type": "string" } },
              "required": Json::array([Json::string("query")]),
            },
          },
        })
      _ => result.push(tool)
    }
  }
  result
}
