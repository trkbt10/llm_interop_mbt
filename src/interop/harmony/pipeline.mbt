///|
/// Full pipeline: Responses API Request -> Chat Completions -> Responses API Response

///|
/// Convert Responses API request to Chat Completions request body
pub fn responses_request_to_chat_completions(request : Json) -> Json {
  let model = match request {
    { "model": String(m), .. } => m
    _ => ""
  }
  let input = match request {
    { "input": Array(items), .. } => items
    _ => []
  }
  let messages = responses_input_to_messages(input)
  let msgs_json = @protocol.messages_to_openai_json(messages)
  // Build Chat Completions body
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs_json),
    "stream": Json::boolean(true),
  }
  // Convert tools
  match request {
    { "tools": Array(tools), .. } =>
      if tools.length() > 0 {
        body["tools"] = Json::array(tools)
        body["tool_choice"] = Json::string("auto")
      }
    _ => ()
  }
  Json::object(body)
}
