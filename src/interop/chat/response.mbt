///|
/// Response transformations for Chat Completions API
///
/// Transforms responses between OpenAI Chat Completions, Anthropic Messages,
/// and Gemini GenerateContent formats.

///|
/// Transform Anthropic Messages response to OpenAI Chat Completions format
pub fn anthropic_response_to_chat(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Extract fields from Anthropic response
  let id = match json {
    { "id": String(id), .. } => id
    _ => ""
  }
  let model = match json {
    { "model": String(m), .. } => m
    _ => ""
  }
  // Collect all text content
  let texts : Array[String] = []
  match json {
    { "content": Array(blocks), .. } =>
      for block in blocks {
        match block {
          { "type": String("text"), "text": String(t), .. } => texts.push(t)
          _ => ()
        }
      }
    _ => ()
  }
  let content = texts.iter().fold(
    init="",
    fn(acc, t) { if acc == "" { t } else { acc + "\n\n" + t } },
  )
  // Build OpenAI format response
  let message : Map[String, Json] = {}
  message["role"] = Json::string("assistant")
  message["content"] = Json::string(content)
  let choice : Map[String, Json] = {}
  choice["index"] = Json::number(0.0)
  choice["message"] = Json::object(message)
  choice["finish_reason"] = Json::string("stop")
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string(model)
  result["choices"] = Json::array([Json::object(choice)])
  Json::object(result).stringify()
}

///|
/// Transform OpenAI Chat Completions response to Anthropic Messages format
pub fn chat_response_to_anthropic(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let id = match json {
    { "id": String(id), .. } => id
    _ => "msg-gateway"
  }
  let model = match json {
    { "model": String(m), .. } => m
    _ => ""
  }
  // Extract content from choices
  let content_text = match json {
    { "choices": Array(choices), .. } =>
      match choices.get(0) {
        Some({ "message": { "content": String(c), .. }, .. }) => c
        _ => ""
      }
    _ => ""
  }
  // Build Anthropic format
  let content_block : Map[String, Json] = {}
  content_block["type"] = Json::string("text")
  content_block["text"] = Json::string(content_text)
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["type"] = Json::string("message")
  result["role"] = Json::string("assistant")
  result["model"] = Json::string(model)
  result["content"] = Json::array([Json::object(content_block)])
  result["stop_reason"] = Json::string("end_turn")
  result["stop_sequence"] = Json::null()
  result["usage"] = Json::object({
    "input_tokens": Json::number(0.0),
    "output_tokens": Json::number(0.0),
  })
  Json::object(result).stringify()
}

///|
/// Transform Gemini GenerateContent response to OpenAI Chat Completions format
pub fn gemini_response_to_chat(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Collect all text from all candidates and parts
  let choices : Array[Json] = []
  let mut idx = 0
  match json {
    { "candidates": Array(candidates), .. } =>
      for candidate in candidates {
        let texts : Array[String] = []
        match candidate {
          { "content": { "parts": Array(parts), .. }, .. } =>
            for part in parts {
              match part {
                { "text": String(t), .. } => texts.push(t)
                _ => ()
              }
            }
          _ => ()
        }
        let content = texts.iter().fold(
          init="",
          fn(acc, t) { if acc == "" { t } else { acc + "\n\n" + t } },
        )
        let message : Map[String, Json] = {}
        message["role"] = Json::string("assistant")
        message["content"] = Json::string(content)
        let choice : Map[String, Json] = {}
        choice["index"] = Json::number(idx.to_double())
        choice["message"] = Json::object(message)
        choice["finish_reason"] = Json::string("stop")
        choices.push(Json::object(choice))
        idx = idx + 1
      }
    _ => ()
  }
  // Generate ID from response or create placeholder
  let id = "gemini-" + idx.to_string()
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string("gemini")
  result["choices"] = Json::array(choices)
  Json::object(result).stringify()
}

///|
/// Transform OpenAI Chat Completions response to Gemini GenerateContent format
pub fn chat_response_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Extract content from choices
  let content_text = match json {
    { "choices": Array(choices), .. } =>
      match choices.get(0) {
        Some({ "message": { "content": String(c), .. }, .. }) => c
        _ => ""
      }
    _ => ""
  }
  // Build Gemini format
  let text_part : Map[String, Json] = {}
  text_part["text"] = Json::string(content_text)
  let content : Map[String, Json] = {}
  content["parts"] = Json::array([Json::object(text_part)])
  content["role"] = Json::string("model")
  let candidate : Map[String, Json] = {}
  candidate["content"] = Json::object(content)
  candidate["finishReason"] = Json::string("STOP")
  candidate["index"] = Json::number(0.0)
  let result : Map[String, Json] = {}
  result["candidates"] = Json::array([Json::object(candidate)])
  result["usageMetadata"] = Json::object({
    "promptTokenCount": Json::number(0.0),
    "candidatesTokenCount": Json::number(0.0),
    "totalTokenCount": Json::number(0.0),
  })
  Json::object(result).stringify()
}
