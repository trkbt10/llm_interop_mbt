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
  let messages : Array[@types.ModelMessage] = []
  // Extract instructions as system message
  match request {
    { "instructions": String(instructions), .. } =>
      messages.push(@types.ModelMessage::System(instructions))
    _ => ()
  }
  // Convert input items to messages
  let input_messages = match request {
    { "input": Array(items), .. } => responses_input_to_messages(items)
    { "input": String(text), .. } =>
      [@types.ModelMessage::User(content=text, name=None)]
    _ => []
  }
  for m in input_messages {
    messages.push(m)
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
      // Responses API function tool: flat {type,name,description,parameters}
      // → Chat Completions: nested {type:"function",function:{name,description,parameters}}
      { "type": String("function"), "name": String(name), .. } => {
        let fn_obj : Map[String, Json] = {}
        fn_obj["name"] = Json::string(name)
        match tool {
          { "description": String(desc), .. } =>
            fn_obj["description"] = Json::string(desc)
          _ => ()
        }
        match tool {
          { "parameters": params, .. } => fn_obj["parameters"] = params
          _ => ()
        }
        match tool {
          { "strict": strict, .. } => fn_obj["strict"] = strict
          _ => ()
        }
        result.push({
          "type": "function",
          "function": Json::object(fn_obj),
        })
      }
      // Already in Chat Completions format (has nested "function" key)
      { "type": String("function"), "function": _, .. } => result.push(tool)
      // Skip non-function tools (container_exec, code_interpreter, etc.)
      // that backends don't understand
      _ => ()
    }
  }
  result
}
