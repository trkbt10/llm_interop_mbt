///|
/// OpenAI Chat Completions gateway behavior

///|
/// Returns the default base URL for the OpenAI Chat Completions API
pub fn chat_completions_default_base_url() -> String {
  "https://api.openai.com/v1"
}

///|
/// Builds the chat completions endpoint path
pub fn chat_completions_path(base_path : String) -> String {
  base_path + "/chat/completions"
}

///|
/// Builds the models listing endpoint path
pub fn chat_completions_models_path(base_path : String) -> String {
  base_path + "/models"
}

///|
/// Builds authentication headers with Bearer token authorization
pub fn chat_completions_auth_headers(api_key : String) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["Authorization"] = "Bearer " + api_key
  headers
}

///|
/// Resolves an incoming HTTP request as a Chat Completions call.
/// Returns `Some((model, body))` if the request matches, `None` otherwise.
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
/// Returns the default base URL for the OpenAI Responses API
pub fn responses_api_default_base_url() -> String {
  "https://api.openai.com/v1"
}

///|
/// Builds the responses endpoint path
pub fn responses_api_path(base_path : String) -> String {
  base_path + "/responses"
}

///|
/// Resolves an incoming HTTP request as a Responses API call.
/// Returns `Some((model, body))` if the request matches, `None` otherwise.
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
