///|
/// Request transformations for Chat Completions API
///
/// Transforms requests between OpenAI Chat Completions, Anthropic Messages,
/// and Gemini GenerateContent formats.

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
