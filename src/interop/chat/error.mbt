///|
/// Error format transformations for Chat Completions API
///
/// Transforms error responses between OpenAI, Anthropic, and Gemini formats.

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
