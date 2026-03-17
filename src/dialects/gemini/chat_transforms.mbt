///|
/// Chat Completions request/response transformations: Gemini <-> OpenAI
///
/// Transforms requests and responses between OpenAI Chat Completions
/// and Gemini GenerateContent formats, plus error format conversions.

///|
/// Transform Gemini GenerateContent request to OpenAI Chat Completions format
pub fn gemini_request_to_chat(body : String, model : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let result : Map[String, Json] = {}
  result["model"] = Json::string(model)
  // Convert contents to messages
  let messages : Array[Json] = []
  match json {
    { "contents": Array(contents), .. } =>
      for content in contents {
        match content {
          { "role": String(role), "parts": Array(parts), .. } => {
            let openai_role = if role == "model" { "assistant" } else { "user" }
            // Extract text from parts
            let texts : Array[String] = []
            for part in parts {
              match part {
                { "text": String(text), .. } => texts.push(text)
                _ => ()
              }
            }
            let content_text = texts.iter().fold(
              init="",
              fn(acc, t) { if acc == "" { t } else { acc + "\n" + t } },
            )
            let msg : Map[String, Json] = {}
            msg["role"] = Json::string(openai_role)
            msg["content"] = Json::string(content_text)
            messages.push(Json::object(msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  // Copy generation config
  match json {
    { "generationConfig": { "maxOutputTokens": max_tokens, .. }, .. } =>
      result["max_tokens"] = max_tokens
    _ => ()
  }
  Json::object(result).stringify()
}

///|
/// Transform OpenAI Chat Completions request to Gemini GenerateContent format
pub fn chat_request_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  // Transform messages to Gemini contents format
  let contents : Array[Json] = []
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          { "role": String(role), "content": content, .. } => {
            let gemini_role = if role == "assistant" { "model" } else { "user" }
            let parts = transform_openai_content_to_gemini(content)
            let content_obj : Map[String, Json] = {}
            content_obj["role"] = Json::string(gemini_role)
            content_obj["parts"] = Json::array(parts)
            contents.push(Json::object(content_obj))
          }
          _ => ()
        }
      }
    _ => ()
  }
  let gemini_body : Map[String, Json] = {}
  gemini_body["contents"] = Json::array(contents)
  Json::object(gemini_body).stringify()
}

///|
/// Transform OpenAI content to Gemini parts format
fn transform_openai_content_to_gemini(content : Json) -> Array[Json] {
  match content {
    String(text) => {
      let part : Map[String, Json] = {}
      part["text"] = Json::string(text)
      [Json::object(part)]
    }
    Array(parts) => {
      let gemini_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["text"] = Json::string(text)
            gemini_parts.push(Json::object(p))
          }
          { "type": String("image_url"), "image_url": { "url": String(url), .. }, .. } =>
            match parse_data_url(url) {
              Some((mime_type, data)) => {
                let inline_data : Map[String, Json] = {}
                inline_data["mime_type"] = Json::string(mime_type)
                inline_data["data"] = Json::string(data)
                let p : Map[String, Json] = {}
                p["inline_data"] = Json::object(inline_data)
                gemini_parts.push(Json::object(p))
              }
              None => ()
            }
          _ => ()
        }
      }
      gemini_parts
    }
    _ => []
  }
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

///|
/// Transform OpenAI error to Gemini error format
pub fn openai_error_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let message = match json {
    { "error": { "message": String(msg), .. }, .. } => msg
    _ => "Unknown error"
  }
  let result : Map[String, Json] = {}
  let error : Map[String, Json] = {}
  error["code"] = Json::number(400.0)
  error["message"] = Json::string(message)
  error["status"] = Json::string("INVALID_ARGUMENT")
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

///|
/// Parse data URL to extract media type and base64 data
fn parse_data_url(url : String) -> (String, String)? {
  if not(url.has_prefix("data:")) {
    return None
  }
  // Find semicolon after "data:"
  let mut semicolon_idx = -1
  let mut idx = 5
  for c in url {
    if idx >= 5 && c == ';' {
      semicolon_idx = idx
      break
    }
    idx = idx + 1
  }
  if semicolon_idx < 0 {
    return None
  }
  // Extract media type
  let mut media_type = ""
  idx = 0
  for c in url {
    if idx >= 5 && idx < semicolon_idx {
      media_type = media_type + c.to_string()
    }
    idx = idx + 1
  }
  // Verify "base64," marker exists after semicolon
  let base64_start = semicolon_idx + 1
  if url.length() < base64_start + 7 {
    return None
  }
  let mut base64_marker = ""
  idx = 0
  for c in url {
    if idx >= base64_start && idx < base64_start + 7 {
      base64_marker = base64_marker + c.to_string()
    }
    idx = idx + 1
  }
  if base64_marker != "base64," {
    return None
  }
  // Extract base64 data (after "base64,")
  let data_start = base64_start + 7
  let mut data = ""
  idx = 0
  for c in url {
    if idx >= data_start {
      data = data + c.to_string()
    }
    idx = idx + 1
  }
  Some((media_type, data))
}
