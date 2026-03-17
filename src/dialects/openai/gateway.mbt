///|
/// OpenAI Chat Completions gateway behavior

///|
pub fn chat_completions_default_base_url() -> String {
  "https://api.openai.com/v1"
}

///|
pub fn chat_completions_path(base_path : String) -> String {
  base_path + "/chat/completions"
}

///|
pub fn chat_completions_models_path(base_path : String) -> String {
  base_path + "/models"
}

///|
pub fn chat_completions_auth_headers(api_key : String) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["Authorization"] = "Bearer " + api_key
  headers
}

///|
pub fn chat_completions_resolve(
  meth : String,
  path : String,
  body : String,
) -> (String, String)? {
  if path == "/v1/chat/completions" && meth == "POST" {
    return Some(("", body))
  }
  None
}

///|
/// OpenAI Responses API gateway behavior

///|
pub fn responses_api_default_base_url() -> String {
  "https://api.openai.com/v1"
}

///|
pub fn responses_api_path(base_path : String) -> String {
  base_path + "/responses"
}

///|
pub fn responses_api_resolve(
  meth : String,
  path : String,
  body : String,
) -> (String, String)? {
  if path == "/v1/responses" && meth == "POST" {
    return Some(("", body))
  }
  None
}
