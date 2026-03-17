///|
/// Chat Completions request/response transformations: Anthropic <-> OpenAI
///
/// Transforms requests and responses between OpenAI Chat Completions
/// and Anthropic Messages formats, plus error format conversions.

///|
/// Transform Anthropic Messages request to OpenAI Chat Completions format
pub fn anthropic_request_to_chat(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let result : Map[String, Json] = {}
  // Copy model
  match json {
    { "model": model, .. } => result["model"] = model
    _ => ()
  }
  // Copy max_tokens
  match json {
    { "max_tokens": max_tokens, .. } => result["max_tokens"] = max_tokens
    _ => ()
  }
  // Build messages array
  let messages : Array[Json] = []
  // Add system message if present
  match json {
    { "system": String(system), .. } => {
      let sys_msg : Map[String, Json] = {}
      sys_msg["role"] = Json::string("system")
      sys_msg["content"] = Json::string(system)
      messages.push(Json::object(sys_msg))
    }
    _ => ()
  }
  // Convert messages
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          { "role": String(role), "content": content, .. } => {
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string(role)
            // Convert Anthropic content format to OpenAI
            new_msg["content"] = transform_anthropic_content_to_openai(content)
            messages.push(Json::object(new_msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  Json::object(result).stringify()
}

///|
/// Transform Anthropic content to OpenAI content format
fn transform_anthropic_content_to_openai(content : Json) -> Json {
  match content {
    String(_) => content
    Array(parts) => {
      let openai_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("text")
            p["text"] = Json::string(text)
            openai_parts.push(Json::object(p))
          }
          {
            "type": String("image"),
            "source": { "data": String(data), "media_type": String(mt), .. },
            ..
          } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("image_url")
            let url = "data:" + mt + ";base64," + data
            p["image_url"] = Json::object({ "url": Json::string(url) })
            openai_parts.push(Json::object(p))
          }
          _ => ()
        }
      }
      Json::array(openai_parts)
    }
    _ => content
  }
}

///|
/// Transform OpenAI Chat Completions request to Anthropic Messages format
pub fn chat_request_to_anthropic(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let result : Map[String, Json] = {}
  // Copy model
  match json {
    { "model": model, .. } => result["model"] = model
    _ => ()
  }
  // Copy or default max_tokens (required by Anthropic)
  match json {
    { "max_tokens": max_tokens, .. } => result["max_tokens"] = max_tokens
    _ => result["max_tokens"] = Json::number(4096.0)
  }
  // Extract system message and convert messages
  let messages : Array[Json] = []
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          { "role": String("system"), "content": String(content), .. } =>
            result["system"] = Json::string(content)
          { "role": String(role), "content": content, .. } => {
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string(role)
            new_msg["content"] = transform_openai_content_to_anthropic(content)
            messages.push(Json::object(new_msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  Json::object(result).stringify()
}

///|
/// Transform OpenAI content to Anthropic content format
fn transform_openai_content_to_anthropic(content : Json) -> Json {
  match content {
    String(_) => content
    Array(parts) => {
      let anthropic_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("text")
            p["text"] = Json::string(text)
            anthropic_parts.push(Json::object(p))
          }
          { "type": String("image_url"), "image_url": { "url": String(url), .. }, .. } =>
            match parse_data_url(url) {
              Some((media_type, data)) => {
                let source : Map[String, Json] = {}
                source["type"] = Json::string("base64")
                source["media_type"] = Json::string(media_type)
                source["data"] = Json::string(data)
                let p : Map[String, Json] = {}
                p["type"] = Json::string("image")
                p["source"] = Json::object(source)
                anthropic_parts.push(Json::object(p))
              }
              None => ()
            }
          _ => ()
        }
      }
      Json::array(anthropic_parts)
    }
    _ => content
  }
}

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
/// Transform Anthropic error to OpenAI error format
pub fn anthropic_error_to_openai(error_obj : Json) -> String {
  let message = match error_obj {
    { "message": String(msg), .. } => msg
    _ => "Unknown error"
  }
  let error_type = match error_obj {
    { "type": String(t), .. } => t
    _ => "api_error"
  }
  let result : Map[String, Json] = {}
  let error : Map[String, Json] = {}
  error["message"] = Json::string(message)
  error["type"] = Json::string(error_type)
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

///|
/// Transform Anthropic error to Gemini error format
pub fn anthropic_error_to_gemini(error_obj : Json) -> String {
  let message = match error_obj {
    { "message": String(msg), .. } => msg
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
/// Transform OpenAI error to Anthropic error format
pub fn openai_error_to_anthropic(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let message = match json {
    { "error": { "message": String(msg), .. }, .. } => msg
    _ => "Unknown error"
  }
  let error_type = match json {
    { "error": { "type": String(t), .. }, .. } => t
    _ => "api_error"
  }
  let result : Map[String, Json] = {}
  result["type"] = Json::string("error")
  let error : Map[String, Json] = {}
  error["type"] = Json::string(error_type)
  error["message"] = Json::string(message)
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

///|
/// Check if response is an Anthropic error format
pub fn is_anthropic_error(json : Json) -> Bool {
  match json {
    { "type": String("error"), "error": _, .. } => true
    _ => false
  }
}

///|
/// Check if response is an OpenAI error format
pub fn is_openai_error(json : Json) -> Bool {
  match json {
    { "error": { "message": String(_), .. }, .. } => true
    _ => false
  }
}

///|
/// Extract error object from Anthropic error response
pub fn extract_anthropic_error(json : Json) -> Json? {
  match json {
    { "type": String("error"), "error": error_obj, .. } => Some(error_obj)
    _ => None
  }
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
